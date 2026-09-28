output "escalation_policy_id" {
  value = module.pagerduty.escalation_policy_id
}

output "service_ids" {
  value = module.pagerduty.service_ids
}

output "security_findings_topic_arn" {
  value = module.threat_detection.findings_topic_arn
}

# Read this after the first apply. It says plainly when findings are being
# generated and going nowhere.
output "security_alerts_pending_confirmation" {
  value = module.threat_detection.pending_confirmations
}
