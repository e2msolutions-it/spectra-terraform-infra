# GitHub push -> CodeBuild (arm64 image build + ECR push) -> [approval] -> ECS deploy.
#
# Triggering: a CodeConnections source action with `detect_changes` watches the
# configured branch. Because your flow is dev -> stag -> main via MERGES, only a
# merge into that branch fires the pipeline - exactly the intended gate.

resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_codebuild_project" "this" {
  name          = var.name
  service_role  = aws_iam_role.build.arn
  build_timeout = var.build_timeout_minutes

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    # ARM_CONTAINER + an aarch64 image means images are built natively for
    # Graviton. Essential for the portal: Next.js pulls platform-specific
    # next/swc binaries and cannot cross-compile.
    type                        = "ARM_CONTAINER"
    compute_type                = var.compute_type
    image                       = var.build_image
    privileged_mode             = true # required to run the Docker daemon
    image_pull_credentials_type = "CODEBUILD"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = local.buildspec
  }
}

resource "aws_codepipeline" "this" {
  name          = var.name
  role_arn      = aws_iam_role.pipeline.arn
  pipeline_type = "V2" # per-execution billing; cheaper than V1 for merge-driven pipelines

  artifact_store {
    type     = "S3"
    location = var.artifact_bucket
    encryption_key {
      id   = var.kms_key_arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"
    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source"]
      configuration = {
        ConnectionArn        = var.connection_arn
        FullRepositoryId     = var.repository_id
        BranchName           = var.branch
        DetectChanges        = true
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAndPush"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source"]
      output_artifacts = ["images"]
      configuration = {
        ProjectName = aws_codebuild_project.this.name
      }
    }
  }

  # Production only: the image is already built and pushed, so approving here
  # gates the ROLLOUT, not the build. Rejecting costs nothing.
  dynamic "stage" {
    for_each = var.require_approval ? [1] : []
    content {
      name = "Approve"
      action {
        name     = "ManualApproval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"
        configuration = {
          CustomData = "Deploy ${var.name} (${var.branch}) to ECS cluster ${var.ecs_cluster_name}?"
        }
      }
    }
  }

  # One deploy action per service, each reading its own imagedefinitions file.
  # They run in parallel (same run_order), so agent-api and worker roll out
  # together.
  stage {
    name = "Deploy"
    dynamic "action" {
      for_each = { for img in var.images : img.key => img if img.ecs_service != "" }
      content {
        name            = "Deploy-${action.value.key}"
        category        = "Deploy"
        owner           = "AWS"
        provider        = "ECS"
        version         = "1"
        input_artifacts = ["images"]
        run_order       = 1
        configuration = {
          ClusterName = var.ecs_cluster_name
          ServiceName = action.value.ecs_service
          FileName    = "imagedefinitions-${action.value.key}.json"
        }
      }
    }
  }
}
