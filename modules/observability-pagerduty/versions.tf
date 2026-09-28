# A module using a provider outside the hashicorp namespace must name its source
# address, or Terraform implicitly asks the registry for hashicorp/pagerduty,
# which does not exist. See the fix committed on 28 September.
terraform {
  required_version = ">= 1.5.7"
  required_providers {
    pagerduty = {
      source  = "PagerDuty/pagerduty"
      version = "~> 3.15"
    }
  }
}
