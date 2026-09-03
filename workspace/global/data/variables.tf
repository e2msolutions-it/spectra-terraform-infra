variable "name" {
  type    = string
  default = "spectra-global-data"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# ---- Scalr remote-state sharing (read the network layer) ----
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
  description = "Scalr workspace name for workspace/global/network."
  type        = string
  default     = "spectra-global-network"
}

variable "db_engine_version" {
  type    = string
  default = "17.5"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_max_allocated_storage" {
  type    = number
  default = 100
}

variable "db_multi_az" {
  type    = bool
  default = true
}
