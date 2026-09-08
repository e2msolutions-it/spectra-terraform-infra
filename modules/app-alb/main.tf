# Public ALB shared by prod + staging. Traffic is split by Host header via
# listener rules that each app cell adds from its own workspace, pointing at its
# own target groups.
resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection
}

# Port 80. Before a certificate exists it serves the placeholder; once HTTPS is
# enabled it becomes a permanent redirect, so plain-HTTP agents/browsers are
# upgraded rather than silently served over cleartext.
# (Resource kept named "placeholder" so enabling HTTPS doesn't force a
# needless destroy/recreate of the already-applied listener.)
resource "aws_lb_listener" "placeholder" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # ONE default_action whose type flips, with the matching nested block made
  # conditional. Using two conditional default_action blocks instead makes the
  # provider see a leftover fixed_response alongside type="redirect" and warn
  # about an invalid attribute combination.
  default_action {
    type = var.certificate_arn == "" ? "fixed-response" : "redirect"

    dynamic "fixed_response" {
      for_each = var.certificate_arn == "" ? [1] : []
      content {
        content_type = "text/plain"
        message_body = var.placeholder_message
        status_code  = "404"
      }
    }

    dynamic "redirect" {
      for_each = var.certificate_arn == "" ? [] : [1]
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

# HTTPS listener. Default action is a 404: every real hostname is matched by a
# host-based rule from an app cell, so an unknown Host gets nothing rather than
# being served the wrong environment.
resource "aws_lb_listener" "https" {
  count             = var.certificate_arn == "" ? 0 : 1
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = var.placeholder_message
      status_code  = "404"
    }
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  count        = var.waf_web_acl_arn == "" ? 0 : 1
  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.waf_web_acl_arn
}

# 301 the apex/www to the marketing site. Sits on the HTTPS listener at a high
# priority number so the per-environment host rules (prod 100-199,
# staging 200-299) are always evaluated first.
resource "aws_lb_listener_rule" "redirect" {
  count = (
    var.certificate_arn != "" &&
    length(var.redirect_hosts) > 0 &&
    var.redirect_target_host != ""
  ) ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = var.redirect_rule_priority

  condition {
    host_header {
      values = var.redirect_hosts
    }
  }

  action {
    type = "redirect"
    redirect {
      host        = var.redirect_target_host
      path        = "/"
      query       = "#{query}"
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}
