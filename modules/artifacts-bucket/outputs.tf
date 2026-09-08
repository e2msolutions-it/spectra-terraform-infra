output "bucket_name" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "s3_base" {
  description = "Pass to spectra-db.sh as S3_BASE."
  value       = "s3://${aws_s3_bucket.this.id}/spectra-db"
}
