# Read the network layer's outputs via Scalr remote-state sharing.
data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    hostname     = var.scalr_hostname
    organization = var.scalr_environment
    workspaces = {
      name = var.network_workspace
    }
  }
}

locals {
  net = data.terraform_remote_state.network.outputs
}

# Single shared PostgreSQL instance (prod + staging share it; separated into
# per-environment logical databases + roles — see README "Logical DB bootstrap").
module "postgres" {
  source = "../../../modules/postgres"

  name                  = var.name
  kms_key_arn           = local.net.kms_key_arn
  private_subnet_ids    = local.net.private_subnet_ids
  rds_security_group_id = local.net.rds_security_group_id
  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  multi_az              = var.db_multi_az
}

# Shared ops bucket holding the DB migration .sql files and the spectra-db.sh
# helper, so a throwaway CloudShell VPC environment (no persistent storage) can
# fetch everything in one command instead of re-uploading each session.
module "db_artifacts" {
  source = "../../../modules/artifacts-bucket"

  name        = var.name
  kms_key_arn = local.net.kms_key_arn
}
