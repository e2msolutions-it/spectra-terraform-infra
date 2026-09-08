variable "name" {
  description = "ALB name, e.g. spectra-prod-01-agent."
  type        = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "waf_web_acl_arn" {
  description = "WAF web ACL to associate (empty to skip)."
  type        = string
  default     = ""
}

variable "placeholder_message" {
  type    = string
  default = "Spectra endpoint - not yet configured"
}

variable "certificate_arn" {
  description = <<-EOT
    ACM certificate for the HTTPS listener. Empty = no HTTPS listener yet
    (Phase-0 state). Passing a cert also switches the port-80 listener from the
    placeholder response to a 301 redirect to HTTPS.
  EOT
  type        = string
  default     = ""
}

variable "ssl_policy" {
  description = "TLS 1.2+ (with TLS 1.3 support). Do not weaken this."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_deletion_protection" {
  description = "Guards the shared ALB against accidental destroy."
  type        = bool
  default     = false
}

# ---- Apex / www redirect to the marketing site ----
variable "redirect_hosts" {
  description = <<-EOT
    Host headers to 301 elsewhere, e.g. ["e2msolutions.net", "www.e2msolutions.net"].
    Lets the shared ALB serve the marketing redirect with no S3 bucket or
    CloudFront distribution - and no extra cost.
  EOT
  type        = list(string)
  default     = []
}

variable "redirect_target_host" {
  description = "Where redirect_hosts should land, e.g. www.e2msolutions.com."
  type        = string
  default     = ""
}

variable "redirect_rule_priority" {
  description = "Kept high so per-environment host rules (100-299) always match first."
  type        = number
  default     = 900
}
