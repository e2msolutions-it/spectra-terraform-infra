# KMS key for data at rest (S3, RDS, Secrets)
resource "aws_kms_key" "data" {
  description             = "${var.name} data-at-rest key"
  deletion_window_in_days = 14
  enable_key_rotation     = true
}

resource "aws_kms_alias" "data" {
  name          = "alias/${var.name}-data"
  target_key_id = aws_kms_key.data.key_id
}

# Baseline security groups (shared across apps in the shared-VPC model)
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Public ALB ingress"
  vpc_id      = var.vpc_id
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.name}-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name        = "${var.name}-ecs-sg"
  description = "ECS tasks; ingress from ALBs only"
  vpc_id      = var.vpc_id
  ingress {
    description     = "From ALB dynamic ports"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.name}-ecs-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "PostgreSQL; ingress from ECS only"
  vpc_id      = var.vpc_id
  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.name}-rds-sg" }
}

# Regional WAF for the public ALBs
# Corporate egress addresses, exempt from the per-IP rate rule only.
#
# count rather than for_each: with an empty list this resource does not exist at
# all, so a cell that has not listed any offices gets exactly the WAF it had
# before - no IP set, no scope-down, no diff.
resource "aws_wafv2_ip_set" "rate_exempt" {
  count = length(var.waf_rate_limit_exempt_ips) > 0 ? 1 : 0

  name               = "${var.name}-rate-exempt"
  description        = "Corporate egress IPs that must not be rate-limited as if they were one machine."
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.waf_rate_limit_exempt_ips
}

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-web-acl"
  description = "Managed rules + rate limiting"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedCommon"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimit"
    priority = 2
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"

        # SCOPE DOWN TO "NOT ONE OF OUR OFFICES". A rate-based statement counts
        # only the requests its scope-down matches, so listed CIDRs are never
        # counted and can never trip the rule, while everyone else is limited
        # exactly as before. The alternative - raising the limit until offices
        # fit under it - would weaken the control for the whole internet in
        # order to fix it for a handful of known addresses.
        dynamic "scope_down_statement" {
          for_each = length(var.waf_rate_limit_exempt_ips) > 0 ? [1] : []
          content {
            not_statement {
              statement {
                ip_set_reference_statement {
                  arn = aws_wafv2_ip_set.rate_exempt[0].arn
                }
              }
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-ratelimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-web-acl"
    sampled_requests_enabled   = true
  }
}
