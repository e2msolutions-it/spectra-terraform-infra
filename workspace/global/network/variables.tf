variable "name" {
  type    = string
  default = "spectra-global-network"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "waf_rate_limit" {
  type    = number
  default = 3000
}

# Corporate egress CIDRs that must not be rate-limited as if they were one
# machine. Empty means nothing changes. Add an office here when it approaches
# ~240 monitored machines behind one public IP - see the module's variable for
# where that number comes from.
variable "waf_rate_limit_exempt_ips" {
  type    = list(string)
  default = []
}
