# State managed by Scalr per workspace. No backend block.
terraform {
  required_version = ">= 1.5.7"
  required_providers {
    pagerduty = {
      source  = "PagerDuty/pagerduty"
      version = "~> 3.15"
    }
  }
}
