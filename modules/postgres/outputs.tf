output "address" {
  value = aws_db_instance.this.address
}

output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "port" {
  value = aws_db_instance.this.port
}

output "identifier" {
  value = aws_db_instance.this.identifier
}

output "master_secret_arn" {
  description = "Secrets Manager ARN with RDS-managed master credentials."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
