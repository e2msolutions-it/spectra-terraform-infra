output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_capacity_provider" {
  value = module.ecs.capacity_provider_name
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "screenshots_bucket" {
  value = module.screenshots.bucket_name
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_user_pool_client_id" {
  value = module.cognito.user_pool_client_id
}

output "db_address" {
  value = local.dat.db_address
}

output "db_name" {
  value = var.db_name
}

output "task_role_arn" {
  value = module.task_iam.task_role_arn
}

output "task_execution_role_arn" {
  value = module.task_iam.task_execution_role_arn
}

output "events_queue_url" {
  value = module.events_queue.queue_url
}

output "events_dlq_url" {
  value = module.events_queue.dlq_url
}

output "worker_role_arn" {
  value = module.task_iam.worker_role_arn
}

output "jwt_secret_arn" {
  value = module.app_secrets.jwt_secret_arn
}

output "jwt_secret_populate_command" {
  description = "Run once after apply - agent-api will not start until the secret has a value."
  value       = module.app_secrets.populate_command
}

output "agent_api_log_group" {
  value = module.agent_api.log_group
}

output "worker_log_group" {
  value = module.worker.log_group
}

output "agent_api_target_group_arn" {
  value = module.agent_api.target_group_arn
}

output "pipeline_api" {
  value = module.pipeline_api.pipeline_name
}

output "pipeline_api_console" {
  value = module.pipeline_api.console_url
}

output "pipeline_portal" {
  value = module.pipeline_portal.pipeline_name
}

output "pipeline_build_log_groups" {
  value = [module.pipeline_api.build_log_group, module.pipeline_portal.build_log_group]
}

output "enrollment_secret_arn" {
  description = "Where the fleet enrollment secret lives. Populate + register it with: spectra-db.sh enroll-secret <database> <this arn>"
  value       = module.app_secrets.enrollment_secret_arn
}

output "portal_log_group" {
  value = module.portal.log_group
}

output "portal_url" {
  value = var.domain_portal == "" ? "" : "https://${var.domain_portal}"
}

output "cognito_hosted_ui" {
  description = "Where the ALB sends people to sign in. Add portal users in this pool (admin-create-user only, MFA required)."
  value       = module.cognito.hosted_ui_base
}

output "portal_force_deploy_command" {
  value = module.portal.force_deploy_command
}
