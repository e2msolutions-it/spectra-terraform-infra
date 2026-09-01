output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "capacity_provider_name" {
  value = aws_ecs_capacity_provider.this.name
}
