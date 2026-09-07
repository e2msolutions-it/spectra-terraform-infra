variable "name" {
  description = "Instance name / prefix, e.g. spectra-prod-01."
  type        = string
}

variable "screenshots_bucket_arn" {
  description = "ARN of this env's screenshots S3 bucket."
  type        = string
}

variable "kms_key_arn" {
  description = "Shared KMS key ARN used to encrypt screenshots."
  type        = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "db_resource_id" {
  description = "RDS DbiResourceId (from global-data), used to scope rds-db:connect."
  type        = string
}

variable "db_name" {
  description = "Logical DB name inside the shared RDS; the app dbuser is <db_name>_app."
  type        = string
}

variable "events_queue_arn" {
  description = "ARN of this env's ingest queue. agent-api may only send; the worker may only receive/delete."
  type        = string
}
