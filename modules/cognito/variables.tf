variable "name" {
  description = "Prefix, e.g. spectra-prod-01."
  type        = string
}

variable "callback_urls" {
  type    = list(string)
  default = ["https://localhost/api/auth/callback/cognito"]
}

variable "logout_urls" {
  type    = list(string)
  default = ["https://localhost"]
}

variable "domain_suffix" {
  description = "Mixed into the Cognito hosted-UI domain to keep it globally unique (prefix domains are shared across all AWS accounts). Pass the account id."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}
