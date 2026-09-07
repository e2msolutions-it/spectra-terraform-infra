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
