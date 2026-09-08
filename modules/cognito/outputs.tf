output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.this.arn
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.portal.id
}

output "user_pool_domain" {
  description = "Cognito hosted-UI domain prefix. The ALB authenticate-cognito action needs this."
  value       = aws_cognito_user_pool_domain.this.domain
}

output "hosted_ui_base" {
  description = "Full hosted-UI URL - useful for building a sign-out link."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.region}.amazoncognito.com"
}
