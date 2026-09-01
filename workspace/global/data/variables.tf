variable "name" {
  type    = string
  default = "spectra-global"
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

# ---- Scalr remote-state sharing (read the network layer) ----
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
  description = "Scalr workspace name for workspace/global/network."
  type        = string
  default     = "global-network"
}

variable "db_engine_version" {
  type    = string
  default = "16.4"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_allocated_storage" {
  type    = number
  default = 100
}

variable "db_max_allocated_storage" {
  type    = number
  default = 1000
}

variable "db_multi_az" {
  type    = bool
  default = true
}
