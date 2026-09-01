output "kms_key_arn" {
  value = aws_kms_key.data.arn
}

output "kms_key_id" {
  value = aws_kms_key.data.key_id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  value = aws_security_group.ecs.id
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.this.arn
}
