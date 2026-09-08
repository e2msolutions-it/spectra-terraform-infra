variable "domain_name" {
  description = "Apex domain for the hosted zone, e.g. e2msolutions.net."
  type        = string
}

variable "create_zone" {
  description = "Create the hosted zone here (true), or look up an existing one (false)."
  type        = bool
  default     = true
}

variable "dns_delegated" {
  description = <<-EOT
    Set true only AFTER the registrar's NS records point at this zone's
    nameservers. ACM validates over public DNS, so until delegation is live the
    validation would just time out. Gating it keeps the first apply fast and
    turns "waiting for DNS" into an explicit step instead of a 20-minute hang.
  EOT
  type        = bool
  default     = false
}
