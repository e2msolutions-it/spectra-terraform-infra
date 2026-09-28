output "findings_topic_arn" {
  description = "Point a PagerDuty or Slack integration at this later without touching any rule."
  value       = aws_sns_topic.findings.arn
}

output "guardduty_detector_id" {
  value = var.enable_guardduty ? aws_guardduty_detector.this[0].id : null
}

output "cloudtrail_bucket" {
  value = var.enable_cloudtrail ? aws_s3_bucket.trail[0].id : null
}

# WHAT STILL NEEDS A HUMAN AFTER APPLY. Printed as an output rather than left
# in a comment, because the failure it prevents is silent: every service on,
# every rule wired, and nobody receiving anything.
output "pending_confirmations" {
  description = "Addresses that must click an AWS confirmation link before any alert reaches them."
  value = length(var.alert_emails) == 0 ? [
    "NO ALERT EMAILS CONFIGURED - findings land in their consoles and reach nobody."
  ] : var.alert_emails
}
