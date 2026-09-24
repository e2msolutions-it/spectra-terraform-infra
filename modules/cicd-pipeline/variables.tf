variable "name" {
  description = "Pipeline name, e.g. spectra-stag-01-api."
  type        = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

# ---- Source ----
variable "connection_arn" {
  description = "Shared CodeConnections (GitHub) connection ARN from global-cicd."
  type        = string
}

variable "repository_id" {
  description = "GitHub repo as owner/name, e.g. e2m-tech/spectra-agent-api."
  type        = string
}

variable "branch" {
  description = "Branch that triggers this pipeline: stag for staging, main for production."
  type        = string
}

# ---- Build ----
variable "images" {
  description = <<-EOT
    One entry per image this repo produces. The api repo produces two
    (agent-api and worker) from the same source tree.

      key             logical name, used for artifact/file names
      dockerfile      path relative to the repo root
      ecr_repository  full ECR repo URL to push to
      container_name  container name in the ECS task definition - MUST match,
                      or the ECS deploy action silently updates nothing
      ecs_service     ECS service to deploy (empty = build/push only, no deploy)
  EOT
  type = list(object({
    key            = string
    dockerfile     = string
    ecr_repository = string
    container_name = string
    ecs_service    = string
  }))
}

variable "build_context" {
  description = "Docker build context relative to the repo root."
  type        = string
  default     = "."
}

variable "compute_type" {
  description = "ARM compute so images build NATIVELY for Graviton. x86 + QEMU would work but is far slower, and Next.js cannot cross-compile at all."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "build_image" {
  description = "aarch64 CodeBuild image - must be ARM to produce arm64 images natively."
  type        = string
  default     = "aws/codebuild/amazonlinux2-aarch64-standard:3.0"
}

# ---- Checks that run BEFORE anything is built ----
variable "sql_checks" {
  description = <<-EOT
    Opt-in. When set, this pipeline replays the repo's SQL against a real
    Postgres and runs its structural assertions BEFORE the first docker build.
    Leave null (the default) and nothing changes - the api pipelines pass
    nothing today and their plans are unaffected.

      migrations_s3_uri     s3://bucket/prefix/migrations - where
                            db-bootstrap/spectra-db.sh publish puts the .sql
                            files. The schema lives in agent-api and the
                            queries live in portal, and the ops bucket is the
                            one place both already agree on.
      artifacts_bucket_arn  that bucket, so the build role can read it.

    WHY THIS RUNS HERE AND NOT IN GITHUB ACTIONS. A workflow was written and
    then deleted: it needed a cross-repo token to reach agent-api's migrations
    from the portal repo, no such token exists, and it was red on every pull
    request. A permanently-failing check is worse than none, because people
    learn to merge past it.

    The earlier reasoning for GitHub was also simply wrong. It argued the check
    must run before the MERGE. What actually matters is before the DEPLOY: on
    22 September the merge was harmless and the deploy was the outage. A check
    that fails here fails the build, so no image is pushed, the Deploy stage
    never runs, and ECS stays on the task definition it is already serving.
    Staging does not go down. That is a strictly better failure than a red tick
    on a pull request somebody merges anyway.

    And the cross-repo problem dissolves: the migrations are already in the ops
    bucket, so this needs an IAM statement rather than a credential.
  EOT
  type = object({
    migrations_s3_uri    = string
    artifacts_bucket_arn = string
  })
  default = null
}

variable "build_timeout_minutes" {
  type    = number
  default = 30
}

# ---- Deploy ----
variable "ecs_cluster_name" {
  type = string
}

variable "require_approval" {
  description = "Insert a manual approval stage before the ECS deploy (production)."
  type        = bool
  default     = false
}

variable "task_role_arns" {
  description = "Task + execution role ARNs the ECS deploy action must be able to iam:PassRole when registering a new task definition revision."
  type        = list(string)
}

# ---- Shared plumbing ----
variable "artifact_bucket" {
  type = string
}

variable "artifact_bucket_arn" {
  type = string
}

variable "kms_key_arn" {
  description = "Shared CMK encrypting the artifact bucket; CodeBuild and CodePipeline both need to use it."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}
