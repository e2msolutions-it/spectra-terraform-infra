resource "pagerduty_escalation_policy" "this" {
  name      = "${var.name}-oncall"
  num_loops = 2

  rule {
    escalation_delay_in_minutes = 15
    dynamic "target" {
      for_each = var.escalation_user_ids
      content {
        type = "user_reference"
        id   = target.value
      }
    }
  }
}

resource "pagerduty_service" "svc" {
  for_each                = toset(var.services)
  name                    = "${var.name}-${each.value}"
  escalation_policy       = pagerduty_escalation_policy.this.id
  auto_resolve_timeout    = var.auto_resolve_timeout
  acknowledgement_timeout = var.ack_timeout
  alert_creation          = "create_alerts_and_incidents"
}
