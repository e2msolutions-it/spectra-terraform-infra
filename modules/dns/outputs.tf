output "zone_id" {
  value = local.zone_id
}

# SET THESE AT THE REGISTRAR to delegate the domain to Route53.
output "name_servers" {
  description = "Point the registrar's NS records for this domain at these, then set dns_delegated = true."
  value       = try(aws_route53_zone.this[0].name_servers, [])
}

output "certificate_arn" {
  description = <<-EOT
    Empty until dns_delegated = true. Resolves to the VALIDATED certificate, so
    anything consuming it implicitly waits for ACM to issue.
  EOT
  value       = try(aws_acm_certificate_validation.this[0].certificate_arn, "")
}

output "certificate_arn_unvalidated" {
  description = "The requested certificate, regardless of validation state (diagnostics)."
  value       = aws_acm_certificate.this.arn
}

output "certificate_status" {
  value = aws_acm_certificate.this.status
}

output "certificate_domains" {
  value = concat([aws_acm_certificate.this.domain_name], tolist(aws_acm_certificate.this.subject_alternative_names))
}
