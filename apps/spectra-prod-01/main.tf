# ---- Isolated per-env compute: own ECS cluster + ASG + capacity provider ----
module "ecs" {
  source = "../../modules/ecs-cluster"

  name                  = local.name
  private_subnet_ids    = local.net.private_subnet_ids
  ecs_security_group_id = local.net.ecs_security_group_id
  instance_type         = var.instance_type
  min_size              = var.ecs_min_size
  max_size              = var.ecs_max_size
  desired_capacity      = var.ecs_desired_capacity
}

# ---- Per-env image registry ----
module "ecr" {
  source = "../../modules/ecr"
  name   = local.name
}

# ---- Per-env screenshots bucket ----
module "screenshots" {
  source      = "../../modules/screenshots-bucket"
  name        = local.name
  kms_key_arn = local.net.kms_key_arn
}

# ---- Per-env Cognito user pool for the portal ----
module "cognito" {
  source        = "../../modules/cognito"
  name          = local.name
  region        = var.region
  domain_suffix = data.aws_caller_identity.current.account_id
  # /oauth2/idpresponse is the ALB's own reserved callback path - authentication
  # is completed by the load balancer, not by an app route.
  callback_urls = var.domain_portal == "" ? ["https://localhost/oauth2/idpresponse"] : ["https://${var.domain_portal}/oauth2/idpresponse"]
  logout_urls   = var.domain_portal == "" ? ["https://localhost"] : ["https://${var.domain_portal}"]
}

# ---- Per-env ingest queue (agent-api sends, worker drains) ----
module "events_queue" {
  source                     = "../../modules/sqs"
  name                       = local.name
  visibility_timeout_seconds = var.events_visibility_timeout_seconds
}

# ---- App IAM roles for the ECS tasks (shared module) ----
module "task_iam" {
  source                 = "../../modules/task-iam"
  name                   = local.name
  screenshots_bucket_arn = module.screenshots.bucket_arn
  kms_key_arn            = local.net.kms_key_arn
  region                 = var.region
  account_id             = data.aws_caller_identity.current.account_id
  db_resource_id         = local.dat.db_resource_id
  db_name                = var.db_name
  events_queue_arn       = module.events_queue.queue_arn
  app_secret_arns        = [module.app_secrets.jwt_secret_arn]
}

# ---- Per-env app secrets (container only; value set out-of-band) ----
module "app_secrets" {
  source      = "../../modules/app-secrets"
  name        = local.name
  kms_key_arn = local.net.kms_key_arn
}

# ---- agent-api: the only internet-facing service ----
module "agent_api" {
  source = "../../modules/ecs-service"

  name                   = "${local.name}-agent-api"
  service_name           = "agent-api"
  cluster_arn            = module.ecs.cluster_arn
  capacity_provider_name = module.ecs.capacity_provider_name
  image                  = "${module.ecr.repository_urls["agent-api"]}:${var.agent_api_image_tag}"
  task_role_arn          = module.task_iam.task_role_arn
  execution_role_arn     = module.task_iam.task_execution_role_arn
  region                 = var.region
  desired_count          = var.agent_api_desired_count
  container_port         = 8080

  attach_to_alb     = true
  vpc_id            = local.net.vpc_id
  listener_arn      = local.edge.https_listener_arn
  host_header       = var.domain_agent
  rule_priority     = var.agent_api_rule_priority
  health_check_path = "/healthz"

  environment = {
    PORT               = "8080"
    AWS_REGION         = var.region
    DB_HOST            = local.dat.db_address
    DB_NAME            = var.db_name
    DB_USER            = "${var.db_name}_app"
    EVENTS_QUEUE_URL   = module.events_queue.queue_url
    SCREENSHOTS_BUCKET = module.screenshots.bucket_name
    JWT_SECRET_ARN     = module.app_secrets.jwt_secret_arn
  }
}

# ---- portal: the human-facing admin + reporting UI ----
# Authentication is done by the ALB (authenticate-cognito on this service's
# listener rule), so the container never sees an anonymous request and holds no
# session secret. It reads Postgres directly with an RDS IAM token - there is no
# separate API tier, because the portal needs database access for the dashboards
# regardless.
module "portal" {
  source = "../../modules/ecs-service"

  name                   = "${local.name}-portal"
  service_name           = "portal"
  cluster_arn            = module.ecs.cluster_arn
  capacity_provider_name = module.ecs.capacity_provider_name
  image                  = "${module.ecr.repository_urls["portal"]}:${var.portal_image_tag}"
  task_role_arn          = module.task_iam.portal_role_arn
  execution_role_arn     = module.task_iam.task_execution_role_arn
  region                 = var.region
  desired_count          = var.portal_desired_count
  container_port         = 3000

  attach_to_alb = true
  vpc_id        = local.net.vpc_id
  listener_arn  = local.edge.https_listener_arn
  host_header   = var.domain_portal
  rule_priority = var.portal_rule_priority
  # Liveness, NOT readiness: /api/readyz touches the database, and a DB blip
  # would otherwise deregister every portal task at once.
  health_check_path = "/api/healthz"

  cognito_user_pool_arn       = module.cognito.user_pool_arn
  cognito_user_pool_client_id = module.cognito.user_pool_client_id
  cognito_user_pool_domain    = module.cognito.user_pool_domain

  environment = {
    PORT       = "3000"
    HOSTNAME   = "0.0.0.0"
    AWS_REGION = var.region
    DB_HOST    = local.dat.db_address
    DB_NAME    = var.db_name
    DB_USER    = "${var.db_name}_app"
  }
}

# ---- worker: drains the queue, no load balancer ----
module "worker" {
  source = "../../modules/ecs-service"

  name                   = "${local.name}-worker"
  service_name           = "worker"
  cluster_arn            = module.ecs.cluster_arn
  capacity_provider_name = module.ecs.capacity_provider_name
  image                  = "${module.ecr.repository_urls["worker"]}:${var.worker_image_tag}"
  task_role_arn          = module.task_iam.worker_role_arn
  execution_role_arn     = module.task_iam.task_execution_role_arn
  region                 = var.region
  desired_count          = var.worker_desired_count

  attach_to_alb = false

  environment = {
    AWS_REGION       = var.region
    DB_HOST          = local.dat.db_address
    DB_NAME          = var.db_name
    DB_USER          = "${var.db_name}_app"
    EVENTS_QUEUE_URL = module.events_queue.queue_url
    RETAIN_MONTHS    = "6"
  }
}

# ---- CI/CD: GitHub merge -> arm64 build -> ECR -> ECS rollout ----
# The api repo yields TWO images from one source tree, so one pipeline builds
# both and deploys both services together.
module "pipeline_api" {
  source = "../../modules/cicd-pipeline"

  name             = "${local.name}-api"
  region           = var.region
  account_id       = data.aws_caller_identity.current.account_id
  connection_arn   = local.cicd.github_connection_arn
  repository_id    = var.api_repository_id
  branch           = var.pipeline_branch
  require_approval = var.pipeline_require_approval

  ecs_cluster_name    = module.ecs.cluster_name
  artifact_bucket     = local.cicd.artifact_bucket
  artifact_bucket_arn = local.cicd.artifact_bucket_arn
  kms_key_arn         = local.net.kms_key_arn

  task_role_arns = [
    module.task_iam.task_role_arn,
    module.task_iam.worker_role_arn,
    module.task_iam.task_execution_role_arn,
  ]

  images = [
    {
      key            = "agent-api"
      dockerfile     = "Dockerfile"
      ecr_repository = module.ecr.repository_urls["agent-api"]
      container_name = module.agent_api.container_name
      ecs_service    = module.agent_api.service_name
    },
    {
      key            = "worker"
      dockerfile     = "Dockerfile.worker"
      ecr_repository = module.ecr.repository_urls["worker"]
      container_name = module.worker.container_name
      ecs_service    = module.worker.service_name
    },
  ]
}

module "pipeline_portal" {
  source = "../../modules/cicd-pipeline"

  name             = "${local.name}-portal"
  region           = var.region
  account_id       = data.aws_caller_identity.current.account_id
  connection_arn   = local.cicd.github_connection_arn
  repository_id    = var.portal_repository_id
  branch           = var.pipeline_branch
  require_approval = var.pipeline_require_approval

  ecs_cluster_name    = module.ecs.cluster_name
  artifact_bucket     = local.cicd.artifact_bucket
  artifact_bucket_arn = local.cicd.artifact_bucket_arn
  kms_key_arn         = local.net.kms_key_arn

  task_role_arns = [
    module.task_iam.portal_role_arn,
    module.task_iam.task_execution_role_arn,
  ]

  images = [
    {
      key            = "portal"
      dockerfile     = "Dockerfile"
      ecr_repository = module.ecr.repository_urls["portal"]
      container_name = module.portal.container_name
      ecs_service    = module.portal.service_name
    },
  ]
}
