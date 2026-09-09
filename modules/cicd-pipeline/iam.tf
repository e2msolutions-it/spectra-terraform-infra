# IAM for the build and pipeline roles. Both are scoped tightly: the build role
# can only push to the specific ECR repos this pipeline owns, and the pipeline
# role can only deploy the named ECS services.

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "build" {
  name               = "${var.name}-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "build" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/codebuild/${var.name}*"]
  }
  statement {
    # GetAuthorizationToken cannot be resource-scoped by AWS.
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    # Pulling base images from ECR Public instead of Docker Hub, to escape
    # Docker Hub's per-IP anonymous rate limit (one NAT gateway = one IP for
    # every build in this VPC). sts:GetServiceBearerToken is what ECR Public
    # authentication actually uses; neither action is resource-scopeable.
    sid       = "EcrPublicLogin"
    actions   = ["ecr-public:GetAuthorizationToken", "sts:GetServiceBearerToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    # Only this pipeline's repos - a compromised build cannot overwrite
    # another environment's images.
    resources = [
      for img in var.images :
      "arn:aws:ecr:${var.region}:${var.account_id}:repository/${replace(img.ecr_repository, "/^[0-9]+\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com\\//", "")}"
    ]
  }
  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketLocation"]
    resources = [var.artifact_bucket_arn, "${var.artifact_bucket_arn}/*"]
  }
  statement {
    sid       = "ArtifactKms"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "build" {
  name   = "${var.name}-codebuild-policy"
  role   = aws_iam_role.build.id
  policy = data.aws_iam_policy_document.build.json
}

# ---------- pipeline role ----------

data "aws_iam_policy_document" "pipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "${var.name}-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume.json
}

locals {
  deploy_services = [for img in var.images : img.ecs_service if img.ecs_service != ""]
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
    resources = [var.artifact_bucket_arn, "${var.artifact_bucket_arn}/*"]
  }
  statement {
    sid       = "ArtifactKms"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
  statement {
    sid       = "UseGithubConnection"
    actions   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
    resources = [var.connection_arn]
  }
  statement {
    sid       = "StartBuild"
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [aws_codebuild_project.this.arn]
  }
  statement {
    # The ECS deploy action does more than call UpdateService: it registers a
    # new task-definition revision, TAGS it, and then POLLS the cluster's tasks
    # to decide whether the rollout succeeded. Miss any of these and the action
    # fails with an insufficient-permissions error rather than a useful one.
    #
    # None of them are resource-scopeable in a way that helps here:
    #   * task definitions have no per-family ARN before they exist
    #   * ListTasks/DescribeTasks are per-TASK ARNs, which are created and
    #     destroyed on every deploy, so they cannot be enumerated up front
    # They are all read-or-tag operations. The one action that actually changes
    # a running service - UpdateService - stays narrowly scoped below.
    sid = "EcsRolloutIntrospection"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:TagResource",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
    ]
    resources = ["*"]
  }
  dynamic "statement" {
    for_each = length(local.deploy_services) > 0 ? [1] : []
    content {
      sid     = "EcsDeploy"
      actions = ["ecs:DescribeServices", "ecs:UpdateService"]
      resources = [
        for svc in local.deploy_services :
        "arn:aws:ecs:${var.region}:${var.account_id}:service/${var.ecs_cluster_name}/${svc}"
      ]
    }
  }
  dynamic "statement" {
    # Required to hand the task/execution roles to the new revision. Scoped to
    # exactly those roles, and only for ECS.
    for_each = length(var.task_role_arns) > 0 ? [1] : []
    content {
      sid       = "PassTaskRoles"
      actions   = ["iam:PassRole"]
      resources = var.task_role_arns
      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "${var.name}-codepipeline-policy"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}
