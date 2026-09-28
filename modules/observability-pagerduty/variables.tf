variable "environments" {
  description = <<-EOT
    One PagerDuty service per entry, named exactly this. These are the app cell
    names, e.g. ["spectra-prod-01", "spectra-stag-01"].

    NOT component names. See the header of main.tf for why the environment is
    the thing worth separating and the component belongs in the alarm name.
  EOT
  type        = list(string)
}

variable "escalation_policy_id" {
  description = <<-EOT
    PagerDuty escalation policy every service routes to.

    A variable rather than a literal so production and staging can diverge later
    without touching this module - the realistic next step being a policy that
    pages for prod and only notifies for stag. The default preserves the ID this
    module was already using.
  EOT
  type        = string
  default     = "PRHK1TH"
}

variable "auto_resolve_timeout" {
  description = "Seconds before PagerDuty auto-resolves an untouched incident. null disables it."
  type        = string
  default     = null
}

variable "ack_timeout" {
  description = "Seconds before an acknowledged incident re-escalates. null disables it."
  type        = string
  default     = null
}
