# Per-env ingest queue: agent-api validates and enqueues, the worker drains it.
# This is what keeps the 9am thundering herd off Postgres.
#
# Encryption: SQS-managed SSE by default (free, encrypted at rest). Pass
# kms_key_arn to switch to the shared CMK if a policy ever requires it.

locals {
  use_cmk = var.kms_key_arn != ""
}

# Poison batches land here instead of blocking the queue forever.
resource "aws_sqs_queue" "dlq" {
  name                       = "${var.name}-events-dlq"
  message_retention_seconds  = var.dlq_retention_seconds
  sqs_managed_sse_enabled    = local.use_cmk ? null : true
  kms_master_key_id          = local.use_cmk ? var.kms_key_arn : null
  kms_data_key_reuse_period_seconds = local.use_cmk ? var.kms_data_key_reuse_period_seconds : null
}

resource "aws_sqs_queue" "events" {
  name                       = "${var.name}-events"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds

  sqs_managed_sse_enabled           = local.use_cmk ? null : true
  kms_master_key_id                 = local.use_cmk ? var.kms_key_arn : null
  kms_data_key_reuse_period_seconds = local.use_cmk ? var.kms_data_key_reuse_period_seconds : null

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

# Only the main queue may feed this DLQ.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.events.arn]
  })
}
