output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Phase 1 attaches more policies (SQS, etc.) to this role."
  value       = aws_iam_role.task.name
}

output "task_execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_execution_role_name" {
  value = aws_iam_role.execution.name
}

output "worker_role_arn" {
  description = "Task role for the ingestion worker (queue + DB only, no S3/KMS)."
  value       = aws_iam_role.worker.arn
}

output "worker_role_name" {
  value = aws_iam_role.worker.name
}
