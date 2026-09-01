output "escalation_policy_id" {
  value = pagerduty_escalation_policy.this.id
}

output "service_ids" {
  value = { for k, s in pagerduty_service.svc : k => s.id }
}
