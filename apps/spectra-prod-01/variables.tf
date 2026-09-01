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
  default = "ap-south-1"
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

# ---- Scalr remote-state sharing (read the global layers) ----
variable "scalr_hostname" {
  description = "Scalr account hostname, e.g. e2m.scalr.io."
  type        = string
  default     = "example.scalr.io"
}

variable "scalr_environment" {
  description = "Scalr environment holding the global workspaces."
  type        = string
  default     = "spectra-global"
}

variable "network_workspace" {
  description = "Scalr workspace for workspace/global/network."
  type        = string
  default     = "global-network"
}

variable "data_workspace" {
  description = "Scalr workspace for workspace/global/data."
  type        = string
  default     = "global-data"
}

variable "compute_workspace" {
  description = "Scalr workspace for workspace/global/compute."
  type        = string
  default     = "global-compute"
}
