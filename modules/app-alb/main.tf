# Public ALB with a Phase-0 placeholder listener. Phase 1 replaces the listener
# with HTTPS (ACM) + target groups wired to the ECS services.
resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_listener" "placeholder" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
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
