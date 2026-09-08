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
  edge = data.terraform_remote_state.edge.outputs
  cicd = data.terraform_remote_state.cicd.outputs
}

# Deferred until Phase 1: only needed now that this cell attaches target groups
# and host-based rules to the shared ALB's HTTPS listener.
data "terraform_remote_state" "edge" {
  backend = "remote"
  config = {
    hostname     = var.scalr_hostname
    organization = var.scalr_environment
    workspaces   = { name = var.edge_workspace }
  }
}

# Shared GitHub connection + artifact bucket for the pipelines below.
data "terraform_remote_state" "cicd" {
  backend = "remote"
  config = {
    hostname     = var.scalr_hostname
    organization = var.scalr_environment
    workspaces   = { name = var.cicd_workspace }
  }
}
