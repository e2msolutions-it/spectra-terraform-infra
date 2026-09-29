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

# ---------------------------------------------------------------------------
# Delivery, part two: WHO IS ALLOWED TO PUBLISH
# ---------------------------------------------------------------------------

# ADDING THIS POLICY REPLACES THE DEFAULT ONE. Until now this topic carried
# the SNS default policy, under which CloudWatch alarms publish fine. An
# EventBridge target does NOT - it publishes as events.amazonaws.com, which the
# default policy does not know, and the publish is refused with nothing
# surfacing on the rule.
#
# SO cloudwatch.amazonaws.com IS LISTED HERE TOO, AND MUST STAY. Dropping it
# would silently disarm all twelve alarms below - they would still transition,
# the apply would still be green, and no incident would ever be raised. That is
# the same failure the KMS key policy caused on 29 Sep, one layer up. If you
# edit this document, re-run the set-alarm-state test afterwards.
#
# The account statement preserves what the default policy gave: Terraform and
# the console manage the topic through IAM either way, but subscription
# management from the account is worth keeping explicit.
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "alarms" {
  statement {
    sid       = "AllowAWSServicesToPublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alarms.arn]
    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com", # the twelve metric alarms - DO NOT REMOVE
        "events.amazonaws.com",     # the task-stopped rule below
      ]
    }
  }

  statement {
    sid     = "AllowAccountOwner"
    actions = ["SNS:Publish", "SNS:Subscribe", "SNS:GetTopicAttributes", "SNS:SetTopicAttributes"]
    resources = [aws_sns_topic.alarms.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.alarms.json
}

# ---------------------------------------------------------------------------
# Crash visibility: the gap the console's "Health status: Unknown" hides
# ---------------------------------------------------------------------------

# WHY UnHealthyHostCount DOES NOT COVER THIS, which is the whole reason these
# three exist. When a container crashes, ECS STOPS the task and DEREGISTERS it
# from the target group. The task is not unhealthy - it is gone. So the
# unhealthy count stays at zero while the healthy count drops, and the alarm
# watching the unhealthy count never fires. A service that crashes, is
# replaced, and crashes again can churn all day: the surviving task keeps
# serving, the site looks fine, and nothing is recorded anywhere a person
# would look.

# TASK COUNT, FROM CONTAINER INSIGHTS - which is already enabled on both
# clusters and already being paid for, and until now nothing read it.
#
# SAFE DURING DEPLOYMENTS BY CONSTRUCTION: the services run
# deployment_minimum_healthy_percent = 100 and maximum = 200, so a rolling
# deploy starts the replacement BEFORE stopping the old task and the running
# count never dips below desired. A dip is therefore always something real,
# which is what lets this alarm be tight rather than hedged.
resource "aws_cloudwatch_metric_alarm" "tasks_below_desired" {
  for_each = var.services

  alarm_name        = "${var.name}-${each.key}-tasks-below-desired"
  alarm_description = "${each.key} is running fewer tasks than it should in ${var.name}. A task exited and has not been replaced - check the stopped-task alert for why."

  comparison_operator = "LessThanThreshold"
  threshold           = 0
  evaluation_periods  = 3

  metric_query {
    id          = "shortfall"
    expression  = "running - desired"
    label       = "tasks short of desired"
    return_data = true
  }

  metric_query {
    id = "running"
    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "RunningTaskCount"
      # MINIMUM, not Average: a task that was down for part of the minute is
      # the fact worth keeping. An average smooths exactly what we are hunting.
      stat        = "Minimum"
      period      = 60
      dimensions = {
        ClusterName = var.ecs_cluster_name
        ServiceName = each.value.service_name
      }
    }
  }

  metric_query {
    id = "desired"
    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "DesiredTaskCount"
      stat        = "Maximum"
      period      = 60
      dimensions = {
        ClusterName = var.ecs_cluster_name
        ServiceName = each.value.service_name
      }
    }
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# THE ONE THAT SAYS WHY. An alarm tells you a task is missing; this carries the
# stop code, the stopped reason and the container's exit code, so the page reads
# "OutOfMemoryError: container killed due to memory usage" instead of leaving
# somebody to go and look.
#
# FILTERING ON stopCode IS WHAT KEEPS DEPLOYMENTS OUT. Every rollout stops
# tasks, and those arrive as ServiceSchedulerInitiated; a human draining an
# instance arrives as UserInitiated. Only these two mean something broke:
#
#   EssentialContainerExited  the process died on its own
#   TaskFailedToStart         it could not start at all - bad image, missing
#                             secret, no capacity
#
# Matching on stoppedReason text instead would be a guessing game against
# strings AWS is free to reword.
resource "aws_cloudwatch_event_rule" "task_stopped" {
  name        = "${var.name}-task-stopped"
  description = "An ECS task in ${var.name} stopped for a reason that is not a deployment."

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Task State Change"]
    detail = {
      clusterArn = [var.ecs_cluster_arn]
      lastStatus = ["STOPPED"]
      stopCode   = ["EssentialContainerExited", "TaskFailedToStart"]
    }
  })
}

resource "aws_cloudwatch_event_target" "task_stopped" {
  rule      = aws_cloudwatch_event_rule.task_stopped.name
  target_id = "sns"
  arn       = aws_sns_topic.alarms.arn

  input_transformer {
    input_paths = {
      group    = "$.detail.group"
      stopcode = "$.detail.stopCode"
      reason   = "$.detail.stoppedReason"
      exitcode = "$.detail.containers[0].exitCode"
      task     = "$.detail.taskArn"
      time     = "$.time"
    }
    input_template = <<-EOT
      "<group> stopped unexpectedly: <stopcode>"
      ""
      "<reason>"
      "container exit code <exitcode>"
      ""
      "<task>"
      "at <time>"
    EOT
  }
}

# WHAT THE PROCESS PRINTED ON ITS WAY OUT. ECS reports that a task stopped;
# only the log says what it was doing. A Go panic and a Node fatal both write a
# recognisable first line before the process dies, and a metric filter turns
# those into something with history and an alarm rather than something you have
# to already suspect before you go looking.
#
# A METRIC FILTER EMITS NOTHING WHEN NOTHING MATCHES - no zero datapoints - so
# treat_missing_data MUST be notBreaching or the alarm sits in INSUFFICIENT_DATA
# forever and never fires when it matters.
#
# This is the only part of this module that costs anything: one custom metric
# per service per environment, about $0.30 each per month.
resource "aws_cloudwatch_log_metric_filter" "fatal" {
  for_each = var.services

  name           = "${var.name}-${each.key}-fatal"
  log_group_name = each.value.log_group
  pattern        = var.log_fatal_pattern

  metric_transformation {
    name      = "${var.name}-${each.key}-fatal"
    namespace = "Spectra/Logs"
    value     = "1"
    # Without this the metric has gaps rather than zeros, and a SUM over a
    # window with no matches is missing rather than 0 - fine here because the
    # alarm treats missing as not breaching, but it makes the graph readable.
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "fatal" {
  for_each = var.services

  alarm_name        = "${var.name}-${each.key}-fatal-log-entry"
  alarm_description = "${each.key} logged a panic or fatal error in ${var.name}. The process printed this on its way out; the stopped-task alert says what happened next."

  namespace   = "Spectra/Logs"
  metric_name = aws_cloudwatch_log_metric_filter.fatal[each.key].metric_transformation[0].name
  statistic   = "Sum"
  period      = 300
  threshold   = 0

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
