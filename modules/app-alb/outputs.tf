output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "http_listener_arn" {
  description = "Placeholder HTTP listener ARN. Phase 1 adds the HTTPS listener + host-based rules."
  value       = aws_lb_listener.placeholder.arn
}
