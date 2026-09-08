# Public entry point: Route53 zone, the shared ALB certificate, the ALB itself,
# and the DNS records pointing at it.
#
# Traffic is split by Host header via listener rules that each app cell adds
# from its own workspace. Rule priority ranges are reserved so the cells never
# collide: prod 100-199, staging 200-299, apex/www redirect 900.
#
# ROLLOUT (two steps, because delegation is a manual registrar action):
#   1. dns_delegated = false -> creates the zone + requests the cert.
#      Take `name_servers` and set them as the NS records at your registrar.
#   2. dns_delegated = true  -> validates the cert (records are written into
#      Route53 automatically), creates the HTTPS listener, turns port 80 into a
#      redirect, and points every hostname at the ALB.
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

# Zone + certificate. No ALB dependency (see modules/dns for why).
module "dns" {
  source = "../../../modules/dns"

  domain_name   = var.domain_name
  create_zone   = var.create_zone
  dns_delegated = var.dns_delegated
}

module "alb" {
  source                = "../../../modules/app-alb"
  name                  = "${var.name}-alb"
  public_subnet_ids     = local.net.public_subnet_ids
  alb_security_group_id = local.net.alb_security_group_id
  waf_web_acl_arn       = local.net.waf_web_acl_arn
  placeholder_message   = "Spectra shared ALB - unknown host"

  # Empty until the certificate is validated, which keeps the HTTPS listener
  # from being attempted with a PENDING certificate.
  certificate_arn = module.dns.certificate_arn

  # Apex + www are 301'd to the marketing site by the ALB itself.
  redirect_hosts       = var.redirect_apex ? [var.domain_name, "www.${var.domain_name}"] : []
  redirect_target_host = var.marketing_host
}

# Hostnames -> ALB. Only created once delegation is live, so we never publish
# records for an endpoint that cannot serve TLS.
module "dns_records" {
  source = "../../../modules/dns-records"
  count  = var.dns_delegated ? 1 : 0

  zone_id      = module.dns.zone_id
  domain_name  = var.domain_name
  alb_dns_name = module.alb.alb_dns_name
  alb_zone_id  = module.alb.alb_zone_id
  hostnames    = var.alb_hostnames
  include_apex = var.redirect_apex
}
