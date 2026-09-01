module "pagerduty" {
  source = "../../../modules/observability-pagerduty"

  name                = var.name
  escalation_user_ids = var.escalation_user_ids
  services            = ["agent-api", "portal", "worker", "rds"]
}
