# Route53 hosted zone + the shared ALB certificate.
#
# Deliberately has NO dependency on the ALB: the ALB needs the certificate ARN,
# so if this module also consumed ALB outputs the two would form a cycle. The
# A/ALIAS records that DO need the ALB live in modules/dns-records.
#
# The certificate covers the apex AND a wildcard:
#   e2msolutions.net     -> so the apex redirect to the .com can serve TLS
#   *.e2msolutions.net   -> spectra, spectra-api, www, and anything added later
# A wildcard alone would NOT cover the apex, which is a common way to end up
# with a certificate error on the bare domain.

resource "aws_route53_zone" "this" {
  count   = var.create_zone ? 1 : 0
  name    = var.domain_name
  comment = "Managed by Terraform (Spectra). Delegate NS at the registrar."
}

data "aws_route53_zone" "existing" {
  count        = var.create_zone ? 0 : 1
  name         = var.domain_name
  private_zone = false
}

locals {
  zone_id = var.create_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.existing[0].zone_id
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Because the zone is in this account, Terraform writes the validation records
# itself - no copying CNAMEs into a registrar panel.
resource "aws_route53_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      type   = o.resource_record_type
      record = o.resource_record_value
    }
  }

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true # apex + wildcard often share one validation record
}

resource "aws_acm_certificate_validation" "this" {
  count                   = var.dns_delegated ? 1 : 0
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]

  timeouts {
    create = "20m"
  }
}
