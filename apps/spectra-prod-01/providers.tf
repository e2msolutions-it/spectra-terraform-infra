provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "spectra"
      Environment = var.environment
      Instance    = var.instance
      Layer       = "app"
      ManagedBy   = "terraform"
    }
  }
}
