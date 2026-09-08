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
  callback_urls = var.domain_portal == "" ? ["https://localhost/api/auth/callback/cognito"] : ["https://${var.domain_portal}/api/auth/callback/cognito"]
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

# ---- worker: drains the queue, no load balancer ----
module "worker" {
  source = "../../modules/ecs-service"

  name                   = "${local.name}-worker"
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
      container_name = "${local.name}-agent-api"
      ecs_service    = module.agent_api.service_name
    },
    {
      key            = "worker"
      dockerfile     = "Dockerfile.worker"
      ecr_repository = module.ecr.repository_urls["worker"]
      container_name = "${local.name}-worker"
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
    module.task_iam.task_role_arn,
    module.task_iam.task_execution_role_arn,
  ]

  # No ecs_service yet: the portal service is added in M3. Until then the
  # pipeline builds and pushes the image but deploys nothing, so merges are
  # already validated end-to-end.
  images = [
    {
      key            = "portal"
      dockerfile     = "Dockerfile"
      ecr_repository = module.ecr.repository_urls["portal"]
      container_name = "${local.name}-portal"
      ecs_service    = ""
    },
  ]
}
