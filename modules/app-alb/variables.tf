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
