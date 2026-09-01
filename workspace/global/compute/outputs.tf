output "cluster_name" {
  value = module.ecs.cluster_name
}

output "cluster_arn" {
  value = module.ecs.cluster_arn
}

output "capacity_provider_name" {
  value = module.ecs.capacity_provider_name
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}
