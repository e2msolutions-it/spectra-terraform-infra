variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "waf_rate_limit" {
  description = "Requests per 5 min per device/IP before WAF rate rule blocks."
  type        = number
  default     = 3000
}
