variable "name" {
  type    = string
  default = "spectra"
}

variable "escalation_user_ids" {
  description = "PagerDuty user IDs on the first escalation rule."
  type        = list(string)
  default     = []
}

variable "services" {
  description = "Alertable services to register in PagerDuty."
  type        = list(string)
  default     = ["agent-api", "portal", "worker", "rds"]
}

variable "auto_resolve_timeout" {
  type    = number
  default = 14400
}

variable "ack_timeout" {
  type    = number
  default = 1800
}
