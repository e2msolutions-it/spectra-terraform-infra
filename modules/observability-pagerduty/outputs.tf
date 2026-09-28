# THE INTEGRATION KEY IS THE ROUTING SECRET. Anything holding it can create
# incidents on that service, so it is marked sensitive: Terraform will not print
# it in plan output or in `terraform output` without -json. It is in state
# either way, which is why state lives in Scalr rather than a file on a laptop.
output "integration_keys" {
  description = "Environment name -> CloudWatch integration key. App cells subscribe their alarm topic to this."
  value       = { for k, i in pagerduty_service_integration.cloudwatch : k => i.integration_key }
  sensitive   = true
}

output "service_ids" {
  description = "Environment name -> PagerDuty service id."
  value       = { for k, s in pagerduty_service.env : k => s.id }
}

# The endpoint an SNS topic subscribes to. Built here rather than in each cell
# so the URL shape is stated once - and PagerDuty auto-confirms the SNS
# subscription, so no human has to click anything for these.
output "integration_urls" {
  description = "Environment name -> the HTTPS endpoint its alarm SNS topic should POST to."
  value = {
    for k, i in pagerduty_service_integration.cloudwatch :
    k => "https://events.pagerduty.com/integration/${i.integration_key}/enqueue"
  }
  sensitive = true
}
