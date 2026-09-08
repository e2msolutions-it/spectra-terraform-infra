# Per-environment application secrets.
#
# IMPORTANT: Terraform creates the secret CONTAINER only - never a
# secret_version. Generating the value here (random_password + a version
# resource) would write the plaintext into Terraform state, which the Spectra
# conventions forbid. The value is set once out-of-band:
#
#   aws secretsmanager put-secret-value --secret-id <arn> \
#     --secret-string "{\"jwt_secret\":\"$(openssl rand -base64 48)\"}"
#
# agent-api reads it at startup via JWT_SECRET_ARN and accepts either a bare
# string or {"jwt_secret": "..."}.
#
# Rotating it invalidates every outstanding device JWT; agents simply re-enroll
# or refresh, so rotation is safe to do at will.

variable "name" {
  description = "Instance name / prefix, e.g. spectra-stag-01."
  type        = string
}

variable "kms_key_arn" {
  description = "Shared CMK so the secret is not encrypted with the AWS-managed default."
  type        = string
}

variable "recovery_window_days" {
  description = "0 = delete immediately (handy in staging); 7-30 keeps an undo window."
  type        = number
  default     = 7
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "${var.name}/jwt-signing-key"
  description             = "HMAC key signing short-lived device JWTs for agent-api (${var.name})."
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.recovery_window_days
}

output "jwt_secret_arn" {
  value = aws_secretsmanager_secret.jwt.arn
}

output "jwt_secret_name" {
  value = aws_secretsmanager_secret.jwt.name
}

output "populate_command" {
  description = "Run once after apply - the secret has no value until you do."
  value       = "aws secretsmanager put-secret-value --region us-east-1 --secret-id ${aws_secretsmanager_secret.jwt.arn} --secret-string \"{\\\"jwt_secret\\\":\\\"$(openssl rand -base64 48)\\\"}\""
}
