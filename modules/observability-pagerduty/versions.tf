# WHY THIS FILE EXISTS, because it looks like boilerplate and is not.
#
# A module that uses pagerduty_* resources without declaring where the provider
# comes from gets an IMPLICIT requirement on hashicorp/pagerduty - Terraform's
# default guess is always the hashicorp namespace. There is no such provider,
# so the real one has to be named here:
#
#   Error: Could not retrieve the list of available versions for provider
#   hashicorp/pagerduty: provider registry registry.terraform.io does not have
#   a provider named registry.terraform.io/hashicorp/pagerduty
#
# It stayed hidden while the root workspace needed only this provider, and
# surfaced the moment the AWS provider was added there and Terraform resolved
# providers from scratch. Declaring it in the module is what the error message
# itself recommends, and is correct regardless of what the root happens to
# declare.
#
# THE OTHER MODULES IN THIS TREE GET AWAY WITHOUT THIS because their implicit
# guess - hashicorp/aws - is the right answer. Any module that ever uses a
# provider outside the hashicorp namespace needs a block like this one.
terraform {
  required_version = ">= 1.5.7"
  required_providers {
    pagerduty = {
      source  = "PagerDuty/pagerduty"
      version = "~> 3.15"
    }
  }
}
