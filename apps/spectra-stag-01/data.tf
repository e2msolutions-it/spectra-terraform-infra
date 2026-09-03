# ---- Cross-layer wiring: Scalr remote-state sharing ----
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

data "aws_caller_identity" "current" {}

locals {
  name = var.instance
  net  = data.terraform_remote_state.network.outputs
  dat  = data.terraform_remote_state.data.outputs
}
