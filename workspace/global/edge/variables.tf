variable "name" {
  type    = string
  default = "spectra-global-edge"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# ---- DNS / TLS ----
variable "domain_name" {
  description = "Apex domain hosted in Route53, e.g. e2msolutions.net."
  type        = string
}

variable "create_zone" {
  description = "Let Terraform create the hosted zone (false = adopt an existing one)."
  type        = bool
  default     = true
}

variable "dns_delegated" {
  description = "Flip to true once the registrar's NS records point at this zone (see the name_servers output)."
  type        = bool
  default     = false
}

variable "alb_hostnames" {
  description = "Subdomain labels routed to the shared ALB."
  type        = list(string)
  default     = ["spectra", "spectra-api", "spectra-stag", "spectra-api-stag"]
}

variable "redirect_apex" {
  description = "Point apex + www at the ALB and 301 them to marketing_host."
  type        = bool
  default     = true
}

variable "marketing_host" {
  description = "Redirect target for apex/www, e.g. www.e2msolutions.com."
  type        = string
  default     = ""
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
