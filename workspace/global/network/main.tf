module "network" {
  source = "../../../modules/network"

  name               = var.name
  region             = var.region
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
}

module "security" {
  source = "../../../modules/security-baseline"

  name           = var.name
  vpc_id         = module.network.vpc_id
  waf_rate_limit = var.waf_rate_limit
}

# Cross-layer wiring is via Scalr remote-state sharing — downstream workspaces
# read the outputs in outputs.tf. No SSM parameters (IDs here are not secrets).
