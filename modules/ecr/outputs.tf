output "repository_urls" {
  value = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
}

output "repository_arns" {
  value = { for k, r in aws_ecr_repository.svc : k => r.arn }
}
