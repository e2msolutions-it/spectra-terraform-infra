# ---- Cross-layer wiring: Scalr remote-state sharing (native types preserved) ----
data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    hostname     = var.scalr_hostname
    organization = var.scalr_environment
    workspaces   = { name = var.network_workspace }
  }
}

data "terraform_remote_state" "data" {
  backend = "remote"
  config = {
    hostname     = var.scalr_hostname
    organization = var.scalr_environment
    workspaces   = { name = var.data_workspace }
  }
}

data "terraform_remote_state" "compute" {
  backend = "remote"
  config = {
    hostname     = var.scalr_hostname
    organization = var.scalr_environment
    workspaces   = { name = var.compute_workspace }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name           = var.instance
  net            = data.terraform_remote_state.network.outputs
  dat            = data.terraform_remote_state.data.outputs
  cmp            = data.terraform_remote_state.compute.outputs
  public_subnets = local.net.public_subnet_ids
  ecr_urls       = local.cmp.ecr_repository_urls
}
