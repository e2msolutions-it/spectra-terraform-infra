variable "name" {
  type = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for storage encryption and the managed master secret."
  type        = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "rds_security_group_id" {
  type = string
}

variable "engine_version" {
  type    = string
  default = "16.4"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "allocated_storage" {
  type    = number
  default = 50
}

variable "max_allocated_storage" {
  type    = number
  default = 500
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "master_username" {
  type    = string
  default = "spectra_admin"
}

variable "deletion_protection" {
  type    = bool
  default = true
}
