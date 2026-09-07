output "queue_url" {
  description = "Set as EVENTS_QUEUE_URL on the agent-api and worker tasks."
  value       = aws_sqs_queue.events.id
}

output "queue_arn" {
  value = aws_sqs_queue.events.arn
}

output "queue_name" {
  value = aws_sqs_queue.events.name
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}
