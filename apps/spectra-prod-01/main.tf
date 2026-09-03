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

# ---- App IAM roles for the ECS tasks ----
data "aws_iam_policy_document" "tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "Screenshots"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${module.screenshots.bucket_arn}/*"]
  }
  statement {
    sid       = "KmsForScreenshots"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [local.net.kms_key_arn]
  }
  statement {
    # App authenticates to Postgres with a short-lived IAM token as its own
    # limited role (spectra_<env>_app); it never receives the RDS master secret.
    sid       = "RdsIamAuth"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:${local.dat.db_resource_id}/${var.db_name}_app"]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "${local.name}-task-policy"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

# Phase 1 adds: ECS task definitions + services on this cluster, target groups,
# and host-based listener rules on the shared ALB (read from global/edge).
