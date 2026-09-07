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
}

resource "aws_iam_role_policy" "task" {
  name   = "${var.name}-task-policy"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}
