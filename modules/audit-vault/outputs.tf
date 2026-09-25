output "bucket_name" {
  description = "Pass to the worker as AUDIT_VAULT_BUCKET."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "retention_days" {
  description = "Echoed so a cell can state the window it actually got, rather than the one it assumed."
  value       = var.default_retention_days
}
