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
