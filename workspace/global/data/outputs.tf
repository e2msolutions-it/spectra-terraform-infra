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

output "db_resource_id" {
  value = module.postgres.resource_id
}

output "db_artifacts_bucket" {
  value = module.db_artifacts.bucket_name
}

output "db_artifacts_s3_base" {
  description = "Pass to spectra-db.sh as S3_BASE."
  value       = module.db_artifacts.s3_base
}
