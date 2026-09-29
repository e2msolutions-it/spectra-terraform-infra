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
#
# RENAMED FROM pending_confirmations 29 Sep, BECAUSE THE NAME WAS A LIE. It is
# var.alert_emails echoed back - it lists who MUST confirm, not who has not,
# and it would have printed the same address forever whether confirmed or not.
# An output that reads as a status and is not one is how the thing it was meant
# to prevent happens anyway. Only SNS knows the truth:
#
#   aws sns list-subscriptions-by-topic --topic-arn <findings_topic_arn>
#
# A SubscriptionArn of "PendingConfirmation" is the unconfirmed state; a real
# ARN means somebody clicked. The link expires after three days.
output "alert_recipients" {
  description = "Addresses subscribed to the findings topic. Each must click an AWS confirmation link once. THIS DOES NOT REPORT WHETHER THEY HAVE - use `aws sns list-subscriptions-by-topic`."
  value = length(var.alert_emails) == 0 ? [
    "NO ALERT EMAILS CONFIGURED - findings land in their consoles and reach nobody."
  ] : var.alert_emails
}
