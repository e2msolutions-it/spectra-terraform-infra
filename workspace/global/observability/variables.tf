variable "pagerduty_token" {
  description = "PagerDuty API token (set as a sensitive Scalr variable)."
  type        = string
  sensitive   = true
}

variable "name" {
  type    = string
  default = "spectra"
}

variable "escalation_user_ids" {
  description = "PagerDuty user IDs for the first on-call escalation rule."
  type        = list(string)
  default     = []
}
