variable "name" {
  description = "Prefix, e.g. spectra-prod-01."
  type        = string
}

variable "kms_key_arn" {
  type = string
}

variable "ia_days" {
  type    = number
  default = 30
}

variable "expire_days" {
  type    = number
  default = 180
}
