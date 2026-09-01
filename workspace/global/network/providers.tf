provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "spectra"
      Layer     = "global"
      Component = "network"
      ManagedBy = "terraform"
    }
  }
}
