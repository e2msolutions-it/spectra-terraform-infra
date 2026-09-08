variable "environment" {
  description = "prod | staging"
  type        = string
}

variable "instance" {
  description = "App instance name / prefix, e.g. spectra-prod-01."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "db_name" {
  description = "Logical database this instance uses inside the shared RDS."
  type        = string
}

variable "domain_agent" {
  description = "Agent API hostname (blank until DNS/ACM is set in Phase 1)."
  type        = string
  default     = ""
}

variable "domain_portal" {
  description = "Portal hostname (blank until DNS/ACM is set in Phase 1)."
  type        = string
  default     = ""
}

# ---- Per-env compute sizing (isolated cluster/ASG) ----
variable "instance_type" {
  description = "arm64 / Graviton (t4g) by default; the ecs-cluster module matches the AMI to it."
  type        = string
  default     = "t4g.small"
}

variable "ecs_min_size" {
  type    = number
  default = 2
}

variable "ecs_max_size" {
  type    = number
  default = 6
}

variable "ecs_desired_capacity" {
  type    = number
  default = 2
}

# ---- Scalr remote-state sharing (read the global layers) ----
variable "scalr_hostname" {
  description = "Scalr account hostname, e.g. e2m.scalr.io."
  type        = string
  default     = "e2msolutions.scalr.io"
}

variable "scalr_environment" {
  description = "Scalr environment holding the global workspaces."
  type        = string
  default     = "env-v0o989ah28npjf8t6"
}

variable "network_workspace" {
  description = "Scalr workspace for workspace/global/network."
  type        = string
  default     = "spectra-global-network"
}

variable "data_workspace" {
  description = "Scalr workspace for workspace/global/data."
  type        = string
  default     = "spectra-global-data"
}

# ---- Ingest queue ----
variable "events_visibility_timeout_seconds" {
  description = "Must exceed the worker's per-batch processing time."
  type        = number
  default     = 60
}

variable "edge_workspace" {
  description = "Scalr workspace for workspace/global/edge (shared ALB + HTTPS listener)."
  type        = string
  default     = "spectra-global-edge"
}

# ---- Images (repos are IMMUTABLE: use a real tag, never :latest) ----
variable "agent_api_image_tag" {
  description = "Immutable tag for the agent-api image, e.g. 20260908-0530."
  type        = string
}

variable "worker_image_tag" {
  description = "Immutable tag for the worker image."
  type        = string
}

# ---- Service sizing ----
variable "agent_api_desired_count" {
  type    = number
  default = 1
}

variable "worker_desired_count" {
  type    = number
  default = 1
}

# ---- Listener rule priorities (prod 100-199, staging 200-299) ----
variable "agent_api_rule_priority" {
  type    = number
  default = 200
}

variable "portal_rule_priority" {
  type    = number
  default = 210
}

# ---- CI/CD ----
variable "cicd_workspace" {
  description = "Scalr workspace for workspace/global/cicd (GitHub connection + artifact bucket)."
  type        = string
  default     = "spectra-global-cicd"
}

variable "api_repository_id" {
  description = "GitHub repo for agent-api + worker, as owner/name."
  type        = string
}

variable "portal_repository_id" {
  description = "GitHub repo for the portal, as owner/name."
  type        = string
}

variable "pipeline_branch" {
  description = "Branch that triggers this environment's pipelines."
  type        = string
  default     = "stag"
}

variable "pipeline_require_approval" {
  description = "Manual approval before the ECS deploy."
  type        = bool
  default     = false
}
