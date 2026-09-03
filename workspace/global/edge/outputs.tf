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
