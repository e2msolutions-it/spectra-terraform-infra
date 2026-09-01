# Exposed for Scalr remote-state sharing (the "Both" wiring).
output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr" {
  value = module.network.vpc_cidr
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "alb_security_group_id" {
  value = module.security.alb_security_group_id
}

output "ecs_security_group_id" {
  value = module.security.ecs_security_group_id
}

output "rds_security_group_id" {
  value = module.security.rds_security_group_id
}

output "kms_key_arn" {
  value = module.security.kms_key_arn
}

output "kms_key_id" {
  value = module.security.kms_key_id
}

output "waf_web_acl_arn" {
  value = module.security.waf_web_acl_arn
}
