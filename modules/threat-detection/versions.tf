# Declared rather than left implicit. hashicorp/aws happens to be the same
# answer Terraform would guess, so this changes nothing today - but a module
# that states its own requirements does not depend on the root happening to
# declare the right thing, which is exactly the assumption that broke
# observability-pagerduty.
terraform {
  required_version = ">= 1.5.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
