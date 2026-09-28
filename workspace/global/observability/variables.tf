variable "name" {
  type    = string
  default = "spectra"
}

variable "escalation_user_ids" {
  description = "PagerDuty user IDs for the first on-call escalation rule."
  type        = list(string)
  default     = []
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# Scalr remote state, for the shared CMK that encrypts the findings topic.
variable "scalr_hostname" {
  description = "Scalr account hostname."
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

variable "security_alert_emails" {
  description = <<-EOT
    Where GuardDuty findings are sent. EMPTY MEANS NOBODY IS TOLD - the
    services run, the findings land in their consoles, and no human hears
    about them. Each address must click an AWS confirmation link before
    anything is delivered.
  EOT
  type        = list(string)
  default     = []
}

variable "enable_aws_config" {
  description = "AWS Config, off by default on cost grounds. See modules/threat-detection/variables.tf."
  type        = bool
  default     = false
}
