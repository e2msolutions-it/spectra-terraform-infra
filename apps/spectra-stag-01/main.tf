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
}

# Phase 1 adds: ECS task definitions + services on this cluster, target groups,
# and host-based listener rules on the shared ALB (read from global/edge).
