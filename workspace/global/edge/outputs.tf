# Consumed by the app cells to attach target groups + host-based listener rules.
output "alb_arn" {
  value = module.alb.alb_arn
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "alb_zone_id" {
  value = module.alb.alb_zone_id
}

output "http_listener_arn" {
  value = module.alb.http_listener_arn
}

output "https_listener_arn" {
  description = "Empty until dns_delegated = true. App cells attach host-based rules here."
  value       = module.alb.https_listener_arn
}

output "https_enabled" {
  value = module.alb.https_enabled
}

# ---- DNS ----
# STEP 1: set these as the NS records for the domain at your registrar.
output "name_servers" {
  description = "Registrar NS records. After propagation, set dns_delegated = true and re-apply."
  value       = module.dns.name_servers
}

output "route53_zone_id" {
  value = module.dns.zone_id
}

output "acm_certificate_arn" {
  description = "Validated certificate (empty until dns_delegated = true)."
  value       = module.dns.certificate_arn
}

output "acm_certificate_status" {
  value = module.dns.certificate_status
}

output "acm_certificate_domains" {
  value = module.dns.certificate_domains
}

output "app_fqdns" {
  description = "Hostnames now resolving to the ALB."
  value       = try(module.dns_records[0].fqdns, [])
}
