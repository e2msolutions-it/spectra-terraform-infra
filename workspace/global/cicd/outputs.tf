# AUTHORISE THIS ONCE in the console before any pipeline can run:
# Developer Tools -> Settings -> Connections -> select it -> "Update pending connection".
output "github_connection_arn" {
  value = aws_codestarconnections_connection.github.arn
}

output "github_connection_status" {
  description = "PENDING until authorised in the console; must read AVAILABLE."
  value       = aws_codestarconnections_connection.github.connection_status
}

output "artifact_bucket" {
  value = module.artifacts.bucket_name
}

output "artifact_bucket_arn" {
  value = module.artifacts.bucket_arn
}
