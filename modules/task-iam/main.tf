# ECS task roles for a Spectra app cell:
#  - execution role: pulls images / writes logs (AWS managed policy)
#  - task role: what the running containers are allowed to do (S3 screenshots,
#    KMS for that bucket, and IAM-token auth to the env's own Postgres role)

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "Screenshots"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${var.screenshots_bucket_arn}/*"]
  }
  statement {
    sid       = "KmsForScreenshots"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
  statement {
    # App authenticates to Postgres with a short-lived IAM token as its own
    # limited role (<db_name>_app); it never receives the RDS master secret.
    sid       = "RdsIamAuth"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${var.region}:${var.account_id}:dbuser:${var.db_resource_id}/${var.db_name}_app"]
  }
  statement {
    # agent-api only ENQUEUES. It cannot read or delete what it wrote, so a
    # compromised API cannot drain or tamper with the backlog.
    sid       = "EnqueueEvents"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
    resources = [var.events_queue_arn]
  }
  dynamic "statement" {
    # Scoped to the listed ARNs only. Critically NOT secretsmanager:* - the RDS
    # master password lives in the same account and must stay unreachable from
    # the app.
    for_each = length(var.app_secret_arns) > 0 ? [1] : []
    content {
      sid       = "ReadAppSecrets"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = var.app_secret_arns
    }
  }
  dynamic "statement" {
    # Needed to decrypt those secrets, since they use the shared CMK.
    for_each = length(var.app_secret_arns) > 0 ? [1] : []
    content {
      sid       = "DecryptAppSecrets"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "${var.name}-task-policy"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

# ---- Worker role: drains the queue and writes to Postgres. Deliberately has
#      NO S3 or KMS access - it only handles metadata, never screenshot bytes.
resource "aws_iam_role" "worker" {
  name               = "${var.name}-worker-task"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "worker" {
  statement {
    sid = "DrainEvents"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [var.events_queue_arn]
  }
  statement {
    sid       = "RdsIamAuth"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${var.region}:${var.account_id}:dbuser:${var.db_resource_id}/${var.db_name}_app"]
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "${var.name}-worker-policy"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

# ---------- portal task role ----------
# The portal is human-facing and reads the database directly (there is no
# separate API tier), so it needs exactly two things and deliberately not a
# third:
#
#   * rds-db:connect as the DML-only app role - it can never alter the schema.
#   * s3:GetObject on the screenshots bucket + kms:Decrypt, so it can presign
#     time-limited GET URLs for the screenshot timeline. Objects are never
#     proxied through the app.
#
# NOT granted: sqs:SendMessage (only agents produce events), s3:PutObject (only
# agents upload), and no access to the app secret - the portal has no signing
# key of its own because the ALB does its authentication.
resource "aws_iam_role" "portal" {
  name               = "${var.name}-portal-task"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "portal" {
  statement {
    sid       = "RdsIamAuth"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${var.region}:${var.account_id}:dbuser:${var.db_resource_id}/${var.db_name}_app"]
  }
  statement {
    sid       = "ReadScreenshots"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.screenshots_bucket_arn, "${var.screenshots_bucket_arn}/*"]
  }
  statement {
    sid       = "DecryptScreenshots"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "portal" {
  name   = "${var.name}-portal-policy"
  role   = aws_iam_role.portal.id
  policy = data.aws_iam_policy_document.portal.json
}
