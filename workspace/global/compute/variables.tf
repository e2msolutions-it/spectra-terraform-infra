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

variable "instance_type" {
  type    = string
  default = "t3.large"
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 8
}

variable "desired_capacity" {
  type    = number
  default = 2
}
