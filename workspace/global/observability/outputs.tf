# escalation_policy_id is GONE. The module stopped creating the policy - it
# now references an existing one by id - so an output reading
# pagerduty_escalation_policy.this.id referred to a resource that no longer
# exists and failed at validate.

output "pagerduty_service_ids" {
  description = "Environment name -> PagerDuty service id."
  value       = module.pagerduty.service_ids
}

# THE APP CELLS READ THIS to subscribe their alarm topic. Sensitive because the
# URL embeds the routing key: anything holding it can raise incidents on that
# service.
output "pagerduty_integration_urls" {
  description = "Environment name -> the HTTPS endpoint its alarm topic POSTs to."
  value       = module.pagerduty.integration_urls
  sensitive   = true
}

output "security_findings_topic_arn" {
  value = module.threat_detection.findings_topic_arn
}

# Needed for `aws guardduty create-sample-findings`, which is how the delivery
# path is tested end to end - and there is no other convenient place to find it.
output "guardduty_detector_id" {
  value = module.threat_detection.guardduty_detector_id
}

# Who alerts are addressed to. NOT a status: it prints the configured list
# whether or not anyone confirmed. See the module output's header for why the
# old name (security_alerts_pending_confirmation) was replaced.
output "security_alert_recipients" {
  value = module.threat_detection.alert_recipients
}
