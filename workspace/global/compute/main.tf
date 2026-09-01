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

# Shared ECS cluster — prod and staging services both run here.
module "ecs" {
  source = "../../../modules/ecs-cluster"

  name                  = var.name
  private_subnet_ids    = local.net.private_subnet_ids
  ecs_security_group_id = local.net.ecs_security_group_id
  instance_type         = var.instance_type
  min_size              = var.min_size
  max_size              = var.max_size
  desired_capacity      = var.desired_capacity
}

# Shared image registry (images are env-agnostic; promote by tag).
module "ecr" {
  source = "../../../modules/ecr"
  name   = "spectra"
}
