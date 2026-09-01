# State + locking are managed by Scalr per workspace (VCS-driven), so there is
# no backend block here. Scalr injects the remote backend at run time.
terraform {
  required_version = ">= 1.5.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
