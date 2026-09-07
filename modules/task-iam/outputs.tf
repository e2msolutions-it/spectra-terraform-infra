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
