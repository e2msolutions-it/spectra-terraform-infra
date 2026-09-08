output "service_name" {
  value = aws_ecs_service.this.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "task_definition_revision" {
  value = aws_ecs_task_definition.this.revision
}

output "log_group" {
  description = "Where to look when a task will not start."
  value       = aws_cloudwatch_log_group.this.name
}

output "target_group_arn" {
  value = try(aws_lb_target_group.this[0].arn, "")
}

output "force_deploy_command" {
  description = "Roll out a Terraform-side task-definition change (env vars etc). Needed because the service ignores task_definition so CI can own it."
  value       = "aws ecs update-service --region ${var.region} --cluster ${element(split("/", var.cluster_arn), length(split("/", var.cluster_arn)) - 1)} --service ${aws_ecs_service.this.name} --task-definition ${aws_ecs_task_definition.this.family} --force-new-deployment"
}
