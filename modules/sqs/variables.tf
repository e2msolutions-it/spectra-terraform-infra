variable "name" {
  description = "Instance name / prefix, e.g. spectra-prod-01."
  type        = string
}

variable "kms_key_arn" {
  description = <<-EOT
    Optional CMK for at-rest encryption. Leave blank to use SQS-managed SSE,
    which is encrypted at rest and free. A CMK is NOT expensive (SQS caches the
    data key for kms_data_key_reuse_period_seconds, so it is a few cents/month,
    not per-request) - SQS-managed SSE is simply the default because activity
    batches carry no credentials and it is one less dependency.
  EOT
  type        = string
  default     = ""
}

variable "visibility_timeout_seconds" {
  description = "Must exceed the worker's per-batch processing time, or messages get redelivered."
  type        = number
  default     = 60
}

variable "message_retention_seconds" {
  description = "How long an undelivered batch survives. 4 days covers a long weekend outage."
  type        = number
  default     = 345600
}

variable "receive_wait_time_seconds" {
  description = "Long polling. 20s means far fewer empty receives (cheaper + lower latency)."
  type        = number
  default     = 20
}

variable "max_receive_count" {
  description = "Deliveries attempted before a batch is parked in the DLQ."
  type        = number
  default     = 5
}

variable "dlq_retention_seconds" {
  description = "DLQ retention - keep the max so poison batches can be inspected."
  type        = number
  default     = 1209600
}

variable "kms_data_key_reuse_period_seconds" {
  description = "Only used when kms_key_arn is set; longer reuse = fewer KMS calls."
  type        = number
  default     = 300
}
