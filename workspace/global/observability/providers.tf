# Set pagerduty_token as a sensitive Scalr workspace variable (env or terraform).
provider "pagerduty" {
  token = var.pagerduty_token
}
