# Per-environment screenshots bucket (data isolation; buckets are free).
module "screenshots" {
  source      = "../../modules/screenshots-bucket"
  name        = local.name
  kms_key_arn = local.net.kms_key_arn
}

# Per-environment Cognito user pool for the portal.
module "cognito" {
  source        = "../../modules/cognito"
  name          = local.name
  callback_urls = var.domain_portal == "" ? ["https://localhost/api/auth/callback/cognito"] : ["https://${var.domain_portal}/api/auth/callback/cognito"]
  logout_urls   = var.domain_portal == "" ? ["https://localhost"] : ["https://${var.domain_portal}"]
}

# Two public ALBs (agent + portal) on the shared VPC, behind the shared WAF.
module "alb_agent" {
  source                = "../../modules/app-alb"
  name                  = "${local.name}-agent"
  public_subnet_ids     = local.public_subnets
  alb_security_group_id = local.net.alb_security_group_id
  waf_web_acl_arn       = local.net.waf_web_acl_arn
  placeholder_message   = "Spectra agent endpoint (${var.environment}) - not yet configured"
}

module "alb_portal" {
  source                = "../../modules/app-alb"
  name                  = "${local.name}-portal"
  public_subnet_ids     = local.public_subnets
  alb_security_group_id = local.net.alb_security_group_id
  waf_web_acl_arn       = local.net.waf_web_acl_arn
  placeholder_message   = "Spectra portal (${var.environment}) - not yet configured"
}

# ---- App IAM roles for the ECS tasks (Phase 1 attaches them to services) ----
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
