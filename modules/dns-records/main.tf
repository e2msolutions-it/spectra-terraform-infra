# A/ALIAS records pointing hostnames at the shared ALB.
#
# Split from modules/dns because these need ALB outputs, while the certificate
# must exist BEFORE the ALB's HTTPS listener - keeping them together would
# create a dependency cycle.
#
# ALIAS (not CNAME) is used throughout: it works on the apex, where CNAMEs are
# illegal, and Route53 charges nothing for alias queries to an AWS target.

variable "zone_id" {
  type = string
}

variable "domain_name" {
  description = "Apex domain, e.g. e2msolutions.net."
  type        = string
}

variable "alb_dns_name" {
  type = string
}

variable "alb_zone_id" {
  type = string
}

variable "hostnames" {
  description = "Subdomain labels to point at the ALB, e.g. [\"spectra\", \"spectra-api\"]."
  type        = list(string)
  default     = []
}

variable "include_apex" {
  description = "Point the apex and www at the ALB too (so it can serve the redirect to the marketing site)."
  type        = bool
  default     = false
}

resource "aws_route53_record" "host" {
  for_each = toset(var.hostnames)

  zone_id = var.zone_id
  name    = "${each.value}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# Apex + www exist only so the ALB can 301 them to the marketing site.
resource "aws_route53_record" "apex" {
  count   = var.include_apex ? 1 : 0
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  count   = var.include_apex ? 1 : 0
  zone_id = var.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = false
  }
}

output "fqdns" {
  value = concat(
    [for r in aws_route53_record.host : r.fqdn],
    try([aws_route53_record.apex[0].fqdn], []),
    try([aws_route53_record.www[0].fqdn], []),
  )
}
