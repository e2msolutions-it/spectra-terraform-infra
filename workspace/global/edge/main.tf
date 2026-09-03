# One shared ALB across prod + staging. Traffic is split by Host header via
# listener rules that each app cell adds (in its own workspace) pointing at its
# target groups. Phase 1 replaces the placeholder listener with HTTPS (ACM).
data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    hostname     = var.scalr_hostname
    organization = var.scalr_environment
    workspaces   = { name = var.network_workspace }
  }
}

locals {
  net = data.terraform_remote_state.network.outputs
}

module "alb" {
  source                = "../../../modules/app-alb"
  name                  = "${var.name}-alb"
  public_subnet_ids     = local.net.public_subnet_ids
  alb_security_group_id = local.net.alb_security_group_id
  waf_web_acl_arn       = local.net.waf_web_acl_arn
  placeholder_message   = "Spectra shared ALB - host rules added per environment"
}
