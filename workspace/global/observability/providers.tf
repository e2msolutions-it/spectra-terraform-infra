# Threat detection is account-level, so it lives beside the alerting rather
# than in an app cell. Same default tags as every other AWS root here.
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "spectra"
      Layer     = "global"
      Component = "observability"
      ManagedBy = "terraform"
    }
  }
}
