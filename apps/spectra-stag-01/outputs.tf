output "screenshots_bucket" {
  value = module.screenshots.bucket_name
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_user_pool_client_id" {
  value = module.cognito.user_pool_client_id
}

output "agent_alb_dns" {
  value = module.alb_agent.alb_dns_name
}

output "portal_alb_dns" {
  value = module.alb_portal.alb_dns_name
}

output "ecs_cluster_name" {
  value = local.cmp.cluster_name
}

output "db_address" {
  value = local.dat.db_address
}

output "db_name" {
  value = var.db_name
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "task_execution_role_arn" {
  value = aws_iam_role.task_execution.arn
}
