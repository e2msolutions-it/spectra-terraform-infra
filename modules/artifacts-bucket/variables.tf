variable "name" {
  description = "Prefix, e.g. spectra-global. Bucket becomes <name>-db-artifacts-<account_id>."
  type        = string
}

variable "suffix" {
  description = "Bucket becomes <name>-<suffix>-<account_id>. e.g. db-artifacts, cicd-artifacts."
  type        = string
  default     = "db-artifacts"
}

variable "kms_key_arn" {
  description = "Shared KMS key for SSE-KMS."
  type        = string
}

variable "noncurrent_version_days" {
  description = <<-EOT
    Versioning is on so re-publishing a migration or the helper script keeps an
    audit trail. Old versions are cleaned up after this many days; CURRENT
    versions never expire - the migration files must stay retrievable.
  EOT
  type        = number
  default     = 90
}
