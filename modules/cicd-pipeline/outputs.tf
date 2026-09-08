output "pipeline_name" {
  value = aws_codepipeline.this.name
}

output "pipeline_arn" {
  value = aws_codepipeline.this.arn
}

output "codebuild_project" {
  value = aws_codebuild_project.this.name
}

output "build_log_group" {
  description = "First place to look when a build fails."
  value       = aws_cloudwatch_log_group.build.name
}

output "console_url" {
  value = "https://${var.region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.this.name}/view?region=${var.region}"
}
