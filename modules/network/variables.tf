variable "name" {
  description = "Resource name prefix (e.g. spectra-global)."
  type        = string
}

variable "region" {
  description = "AWS region (for the S3 gateway endpoint)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway (cheaper) instead of one per AZ."
  type        = bool
  default     = true
}

