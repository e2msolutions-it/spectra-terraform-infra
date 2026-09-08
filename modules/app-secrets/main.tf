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

# ---------------------------------------------------------------------------
# Fleet enrollment secret.
#
# This is the ONE value baked into the MSI config for the whole fleet (factor 1
# of enrollment; factor 2 is device_allowlist). agent-api never reads it from
# here - it only ever compares sha256(presented secret) against
# agent_enrollment.token_hash in the database. So the task role deliberately
# gets NO access to this secret; it exists purely so ops has one durable,
# encrypted, auditable place to fetch the plaintext when repackaging the MSI.
#
# Container only, no version - same reason as the JWT key above. Populate and
# register it in one step with:
#
#   ./db-bootstrap/spectra-db.sh enroll-secret <database> <this-arn>
#
# Rotation: run that command again. It revokes the old agent_enrollment row and
# inserts the new hash, so already-enrolled devices keep working (they
# authenticate with their keypair, not the enrollment secret) and only NEW
# installs need the updated MSI.
resource "aws_secretsmanager_secret" "enrollment" {
  name                    = "${var.name}/agent-enrollment-secret"
  description             = "Shared fleet enrollment secret for the Spectra Windows agent (${var.name}). Baked into the MSI config."
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.recovery_window_days
}

output "enrollment_secret_arn" {
  value = aws_secretsmanager_secret.enrollment.arn
}

output "enrollment_secret_name" {
  value = aws_secretsmanager_secret.enrollment.name
}
