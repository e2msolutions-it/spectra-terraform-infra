# PagerDuty: ONE SERVICE PER ENVIRONMENT, not one per ECS service.
#
# WHAT CHANGED AND WHY. This module used to create a service per component -
# spectra-agent-api, spectra-portal, spectra-worker, spectra-rds - with no
# environment anywhere in the name. There is exactly one observability
# workspace shared by both environments, so a staging incident and a production
# incident would have arrived at the same service, in front of the same
# rotation, indistinguishable.
#
# It had not bitten yet only because nothing routed to those services: there
# were no integrations and no alarms. They were declared intent.
#
# THE ENVIRONMENT IS THE THING WORTH SEPARATING. "The portal is down" means
# something entirely different in spectra-prod-01 than in spectra-stag-01 - one
# is an outage, the other is a Tuesday. Which COMPONENT broke is a detail of the
# incident, and it arrives in the alert payload where it belongs. Four services
# per environment would be eight escalation paths for a rotation of one or two
# people: an org chart for a team that does not have one.
#
# Separating by environment is also what makes muting possible. A single shared
# service can only be all-on or all-off; with one per environment, staging can
# be silenced for a week without touching production, which is the realistic
# thing somebody will want to do.
#
# ---------------------------------------------------------------------------
# THE COMPONENT LIVES IN THE ALARM NAME, and the naming is load-bearing.
#
#   spectra-prod-01-portal-5xx-error
#   spectra-prod-01-portal-cpu-usage-high
#   spectra-stag-01-events-dlq-not-empty
#
# <environment>-<component>-<condition>. PagerDuty groups and de-duplicates on
# the alarm name, so this shape gives one incident per real problem rather than
# one per datapoint, and a person reading a phone at 2am knows which system and
# which environment before opening anything.

resource "pagerduty_service" "env" {
  for_each = toset(var.environments)

  # The service IS the environment. No prefix: "spectra-prod-01" is already
  # unambiguous, and "spectra-spectra-prod-01" is what a prefix would produce.
  name                    = each.value
  description             = "Spectra ${each.value} - alarms from CloudWatch. Component and condition are in the alert name."
  escalation_policy       = var.escalation_policy_id
  auto_resolve_timeout    = var.auto_resolve_timeout
  acknowledgement_timeout = var.ack_timeout

  # An alarm that recovers should close its own incident. Without this the
  # OK transition is recorded as a new alert on an open incident and somebody
  # has to resolve by hand, which is how a board fills with things that fixed
  # themselves hours ago.
  alert_creation = "create_alerts_and_incidents"
}

# The AWS CloudWatch vendor, looked up rather than hardcoded as an opaque ID.
# It parses the SNS envelope CloudWatch sends, so alarm name, state, reason and
# dimensions arrive as fields instead of as a wall of JSON.
data "pagerduty_vendor" "cloudwatch" {
  name = "Amazon CloudWatch"
}

resource "pagerduty_service_integration" "cloudwatch" {
  for_each = pagerduty_service.env

  name    = "CloudWatch"
  service = each.value.id
  vendor  = data.pagerduty_vendor.cloudwatch.id
}
