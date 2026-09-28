# CloudWatch alarms for one app cell, routed to that environment's PagerDuty
# service.
#
# NAMING IS THE INTERFACE: <environment>-<component>-<condition>.
#
#   spectra-prod-01-portal-5xx-error
#   spectra-prod-01-portal-cpu-usage-high
#   spectra-stag-01-events-dlq-not-empty
#
# PagerDuty groups and de-duplicates on the alarm name, so this shape produces
# one incident per real problem rather than one per datapoint, and somebody
# reading a phone at 2am knows the environment and the system before opening
# anything. It is worth keeping mechanical.
#
# ---------------------------------------------------------------------------
# WHAT IS ALARMED, AND WHAT DELIBERATELY IS NOT.
#
# Every alarm here answers "is a person needed?". Metrics that are interesting
# but not actionable belong on a dashboard, not in a rotation. The fastest way
# to make an alerting system useless is to route everything to it.
#
# NOT ALARMED, on purpose:
#   * Request count, latency percentiles - interesting, and a human cannot do
#     anything about them at 2am that waiting until morning would not.
#   * Screenshot volume, sample throughput - product metrics. The portal shows
#     them; a dip is a question, not an incident.
#   * RDS. The database is SHARED between environments and lives in
#     global/data, so alarms on it belong there rather than being declared
#     twice here with two different services fighting over who gets paged.
#
# ---------------------------------------------------------------------------
# treat_missing_data IS THE SUBTLE ONE, and getting it wrong is how alarms lose
# their credibility.
#
# ECS publishes CPU and memory only while tasks are running. A service scaled to
# zero - deliberately, or mid-deployment - produces no datapoints at all. With
# missing data treated as breaching, every intentional scale-down pages
# somebody. So these use notBreaching: the alarm answers "is it too hot", not
# "is it alive". Whether it is alive is what the unhealthy-host alarm is for,
# and that one comes from the load balancer, which does keep reporting.

locals {
  # Services that sit behind the load balancer get HTTP alarms; the worker has
  # no target group, so it gets ECS alarms only. Keyed by component name, which
  # is what lands in the alarm name.
  http_services = { for k, v in var.services : k => v if v.target_group_arn_suffix != "" }
}

# ---------------------------------------------------------------------------
# Delivery
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  name              = "${var.name}-alarms"
  kms_master_key_id = var.kms_key_arn
}

# PAGERDUTY AUTO-CONFIRMS THIS SUBSCRIPTION, unlike an email one - the
# CloudWatch integration answers the SNS confirmation itself. So unlike the
# security findings topic, nobody has to click a link and there is no window
# where alarms fire into nothing.
#
# The endpoint embeds the routing key, which is why it arrives as a sensitive
# value and is not echoed in any output here.
resource "aws_sns_topic_subscription" "pagerduty" {
  count = var.pagerduty_integration_url == "" ? 0 : 1

  topic_arn              = aws_sns_topic.alarms.arn
  protocol               = "https"
  endpoint               = var.pagerduty_integration_url
  endpoint_auto_confirms = true
}

# ---------------------------------------------------------------------------
# HTTP: is it returning errors, and is anything behind the load balancer?
# ---------------------------------------------------------------------------

# 5xx FROM THE TARGET, NOT FROM THE LOAD BALANCER. HTTPCode_ELB_5XX_Count
# includes the ALB's own 502/503 when it has no healthy target - which the
# unhealthy-host alarm below already covers, and counting it here would page
# twice for one problem. HTTPCode_Target_5XX_Count is the application saying it
# failed, which is a different fact.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  for_each = local.http_services

  alarm_name        = "${var.name}-${each.key}-5xx-error"
  alarm_description = "${each.key} returned 5xx responses in ${var.name}. The application is failing requests, not the load balancer."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  statistic   = "Sum"
  period      = 300
  # A threshold, not zero. One 5xx is a bad request somewhere; a handful in five
  # minutes is a pattern. Zero would page on every transient blip and get muted.
  threshold           = var.threshold_5xx_per_5min
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = each.value.target_group_arn_suffix
  }

  # No 5xx means no datapoint, which is the healthy state.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# THE ONE THAT MEANS "IT IS DOWN". Everything else here is a degradation; this
# is the load balancer reporting it has nothing healthy to send traffic to.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  for_each = local.http_services

  alarm_name        = "${var.name}-${each.key}-unhealthy-hosts"
  alarm_description = "${each.key} has unhealthy targets in ${var.name}. If this equals the task count, the service is down."

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  statistic   = "Maximum"
  period      = 60
  threshold   = 1

  comparison_operator = "GreaterThanOrEqualToThreshold"
  # Two consecutive minutes, so a task being replaced during an ordinary
  # deployment does not page. A rollout that leaves something unhealthy for
  # longer than that is not an ordinary deployment.
  evaluation_periods = 2

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = each.value.target_group_arn_suffix
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# ECS: is it too hot?
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = var.services

  alarm_name        = "${var.name}-${each.key}-cpu-usage-high"
  alarm_description = "${each.key} sustained high CPU in ${var.name}."

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  statistic   = "Average"
  period      = 300
  threshold   = var.threshold_cpu_percent

  comparison_operator = "GreaterThanThreshold"
  # Ten minutes, not five. These instances are t4g burstables and a single
  # busy five-minute window is normal - the rollup runs, a batch drains. Two
  # consecutive windows is a trend.
  evaluation_periods = 2

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = each.value.service_name
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each = var.services

  alarm_name        = "${var.name}-${each.key}-memory-usage-high"
  alarm_description = "${each.key} sustained high memory in ${var.name}. Unlike CPU this rarely recovers on its own - a container near its limit is usually heading for an OOM kill."

  namespace   = "AWS/ECS"
  metric_name = "MemoryUtilization"
  statistic   = "Average"
  period      = 300
  threshold   = var.threshold_memory_percent

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = each.value.service_name
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# Ingestion: is the queue draining?
# ---------------------------------------------------------------------------

# AGE OF THE OLDEST MESSAGE, NOT QUEUE DEPTH. Depth is meaningless on its own -
# the 9am herd produces a large, entirely healthy spike that drains in minutes,
# and alarming on it would page every single morning. Age answers the question
# that matters: is anything STUCK. A backlog that is being worked through keeps
# its oldest message young.
resource "aws_cloudwatch_metric_alarm" "queue_backlog" {
  alarm_name        = "${var.name}-events-queue-backlog"
  alarm_description = "The oldest unprocessed event in ${var.name} is older than ${var.threshold_queue_age_seconds}s. The worker is not keeping up, or is not running."

  namespace   = "AWS/SQS"
  metric_name = "ApproximateAgeOfOldestMessage"
  statistic   = "Maximum"
  period      = 300
  threshold   = var.threshold_queue_age_seconds

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2

  dimensions = { QueueName = var.events_queue_name }

  # An empty queue reports nothing. That is the healthy state.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ANY MESSAGE IN THE DEAD LETTER QUEUE IS WORTH A LOOK, so the threshold is
# zero rather than a number. Ingestion writes are idempotent and a failed batch
# redelivers, so a message reaching the DLQ means it failed repeatedly - a
# malformed envelope, or a bug. Those do not fix themselves, and they are data
# the fleet has already sent and will not send again.
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name        = "${var.name}-events-dlq-not-empty"
  alarm_description = "Messages are in the ${var.name} dead letter queue. Something failed repeatedly - inspect before they age out."

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  statistic   = "Maximum"
  period      = 300
  threshold   = 0

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1

  dimensions = { QueueName = var.dlq_name }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
