# An ECS-on-EC2 service, optionally behind the shared ALB.
#
# NETWORK MODE: "bridge" with a DYNAMIC host port (hostPort = 0), not awsvpc.
# On EC2, awsvpc gives every task its own ENI, and ENIs are capped per instance
# type - a t4g.small allows only ~2 task ENIs, which would throttle placement
# and waste the box. Bridge networking has no such limit, and the ECS security
# group already permits ALB -> tasks across the ephemeral port range, which is
# exactly what dynamic port mapping needs. Target groups therefore use
# target_type = "instance".
#
# ARCHITECTURE: runtime_platform pins ARM64 to match the Graviton (t4g)
# instances. Without it a mismatched image fails to start with an unhelpful
# error.

resource "aws_cloudwatch_log_group" "this" {
  name              = "/spectra/${var.name}"
  retention_in_days = var.log_retention_days
}

locals {
  # Cluster-scoped identity. Falls back to the prefixed name so callers that
  # do not set service_name behave exactly as before.
  svc = var.service_name != "" ? var.service_name : var.name

  # Dynamic host port: hostPort 0 lets ECS pick a free ephemeral port, so many
  # tasks of the same service can share one instance.
  port_mappings = var.attach_to_alb ? [{
    containerPort = var.container_port
    hostPort      = 0
    protocol      = "tcp"
  }] : []

  container = merge(
    {
      name              = local.svc
      image             = var.image
      essential         = true
      cpu               = var.cpu
      memory            = var.memory
      memoryReservation = var.memory_reservation
      portMappings      = local.port_mappings
      environment       = [for k, v in var.environment : { name = k, value = v }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    length(var.command) > 0 ? { command = var.command } : {}
  )
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.execution_role_arn
  container_definitions    = jsonencode([local.container])

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
}

# ---------- ALB attachment (agent-api / portal) ----------

resource "aws_lb_target_group" "this" {
  count = var.attach_to_alb ? 1 : 0

  name                 = substr("${var.name}-tg", 0, 32)
  port                 = var.container_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # The service references this TG, so replacements must create the new one
  # before destroying the old.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "this" {
  count = var.attach_to_alb && var.listener_arn != "" && var.host_header != "" ? 1 : 0

  listener_arn = var.listener_arn
  priority     = var.rule_priority

  condition {
    host_header {
      values = [var.host_header]
    }
  }

  # Authentication happens HERE, at the edge, when a Cognito pool is supplied -
  # not inside the application. An anonymous request is redirected to the
  # Cognito hosted UI and never reaches the container; the ALB completes the
  # OIDC code flow at its reserved /oauth2/idpresponse path and then forwards
  # the request with a signed x-amzn-oidc-data header carrying the identity.
  #
  # Consequences worth knowing:
  #   * No session secret, callback route or auth library in the app, and no way
  #     to render a page before the auth check - the request does not arrive.
  #   * order matters: authenticate must precede forward.
  #   * The TARGET GROUP health check is unaffected. Health checks are sent by
  #     the ALB straight to the target and never traverse listener rules, so
  #     /healthz does not need excluding here.
  #   * agent-api passes no pool: devices authenticate with signed requests, and
  #     an OIDC redirect would break them.
  dynamic "action" {
    for_each = var.cognito_user_pool_arn != "" ? [1] : []
    content {
      type  = "authenticate-cognito"
      order = 1
      authenticate_cognito {
        user_pool_arn       = var.cognito_user_pool_arn
        user_pool_client_id = var.cognito_user_pool_client_id
        user_pool_domain    = var.cognito_user_pool_domain
        # An expired session re-runs the login flow rather than returning 401,
        # which is what a human in a browser wants.
        on_unauthenticated_request = "authenticate"
        scope                      = "openid email profile"
        session_timeout            = var.auth_session_timeout_seconds
      }
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
    order            = var.cognito_user_pool_arn != "" ? 2 : null
  }
}

# ---------- Service ----------

resource "aws_ecs_service" "this" {
  # Cluster-scoped, so it does not need the env prefix. NOTE: this is ForceNew -
  # renaming an existing service destroys and recreates it.
  name            = local.svc
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  enable_execute_command = var.enable_execute_command

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    weight            = 1
    base              = 0
  }

  # 100/200 lets a deploy start replacements before draining the old tasks,
  # which needs spare capacity on the ASG - fine with managed scaling.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }
  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  dynamic "load_balancer" {
    for_each = var.attach_to_alb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = local.svc
      container_port   = var.container_port
    }
  }

  health_check_grace_period_seconds = var.attach_to_alb ? var.health_check_grace_period_seconds : null

  # The rule must exist before the service registers targets, or the first
  # deploy can report healthy while nothing routes to it.
  depends_on = [aws_lb_listener_rule.this]

  lifecycle {
    # CodePipeline's ECS deploy action registers a NEW task-definition revision
    # on every deploy. Without this, the next `terraform apply` would drag the
    # service back to the revision Terraform knows about - silently reverting
    # production to an older image. Terraform creates the service and its FIRST
    # task definition; CI owns every revision after that.
    #
    # CONSEQUENCE: changing `environment` here creates a new task-definition
    # revision that the running service will NOT pick up. To roll out a config
    # change, either trigger the pipeline or force it once:
    #   aws ecs update-service --cluster <cluster> --service <svc> \
    #     --task-definition <family> --force-new-deployment
    # (the `force_deploy_command` output prints this ready to paste)
    ignore_changes = [task_definition]
  }
}
