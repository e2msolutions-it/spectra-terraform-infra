output "db_address" {
  value = module.postgres.address
}

output "db_endpoint" {
  value = module.postgres.endpoint
}

output "db_port" {
  value = module.postgres.port
}

output "db_identifier" {
  value = module.postgres.identifier
}

output "db_master_secret_arn" {
  value = module.postgres.master_secret_arn
}
