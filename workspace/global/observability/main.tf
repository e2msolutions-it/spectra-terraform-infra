# ONE SERVICE PER ENVIRONMENT, not per component. A staging incident and a
# production incident used to arrive at the same PagerDuty service, in front of
# the same rotation, indistinguishable - which had not bitten only because
# nothing routed to them. The component is in the alarm name instead; see the
# module header.
module "pagerduty" {
  source = "../../../modules/observability-pagerduty"

  environments = var.environments
}

# Shared CMK for the findings topic. Nothing else is needed from network here.
data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    hostname     = var.scalr_hostname
    organization = var.scalr_environment
    workspaces = {
      name = var.network_workspace
    }
  }
}

# GuardDuty, a durable CloudTrail, optional AWS Config, and an SNS topic so
# findings reach a person rather than a console nobody opens. PagerDuty is not
# the route today because escalation_user_ids above is still unset - an alert
# sent there would page nobody. The module's topic ARN is an output, so
# pointing it at PagerDuty later changes one subscription and no rules.
module "threat_detection" {
  source = "../../../modules/threat-detection"

  name         = var.name
  kms_key_arn  = data.terraform_remote_state.network.outputs.kms_key_arn
  alert_emails = var.security_alert_emails

  enable_config = var.enable_aws_config
}
