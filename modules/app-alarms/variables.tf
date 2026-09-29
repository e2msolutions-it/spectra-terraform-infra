variable "name" {
  description = "The app cell name, e.g. spectra-prod-01. Every alarm is prefixed with it, and it must match the PagerDuty service name exactly."
  type        = string
}

variable "kms_key_arn" {
  description = "Shared CMK encrypting the alarm topic."
  type        = string
}

variable "pagerduty_integration_url" {
  description = <<-EOT
    The environment's PagerDuty CloudWatch endpoint, from the observability
    workspace. Empty creates the topic and the alarms but no subscription -
    alarms then fire into a topic with no subscriber, which is a legitimate
    first-apply state and not somewhere to stay.

    PagerDuty auto-confirms this subscription, so no human has to click a link.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "alb_arn_suffix" {
  description = "From the edge workspace. CloudWatch's LoadBalancer dimension, not the ARN."
  type        = string
}

variable "ecs_cluster_name" {
  type = string
}

# Needed by the task-stopped rule, which matches on clusterArn. ECS task state
# change events are account-wide on the default bus, so without this filter
# each cell would page for the other environment's crashes too.
variable "ecs_cluster_arn" {
  type = string
}

variable "services" {
  description = <<-EOT
    Component name -> its ECS service and target group. The KEY is what appears
    in the alarm name, so "portal" produces spectra-prod-01-portal-cpu-usage-high.

    A service with an empty target_group_arn_suffix (the worker) gets ECS alarms
    only - there is no load balancer in front of it to report 5xx or unhealthy
    hosts, and inventing those would produce alarms that can never fire.
  EOT
  type = map(object({
    service_name            = string
    target_group_arn_suffix = string
    log_group               = string
  }))
}

variable "events_queue_name" {
  type = string
}

variable "dlq_name" {
  type = string
}

# ---- Thresholds ----
# Starting values, set against what this system actually does rather than from
# a template. Every one of them should move once there is real traffic to
# compare against; the load generator exists partly to produce that.

variable "threshold_5xx_per_5min" {
  description = "Target 5xx responses in five minutes before paging. Not zero - one 5xx is a bad request, a handful is a pattern."
  type        = number
  default     = 5
}

variable "threshold_cpu_percent" {
  description = "Sustained CPU over two consecutive five-minute windows. 80 on t4g burstables, which are expected to spike."
  type        = number
  default     = 80
}

variable "threshold_memory_percent" {
  description = "Sustained memory. Higher than CPU because memory pressure rarely recovers on its own - by the time it is sustained, an OOM kill is usually next."
  type        = number
  default     = 85
}

variable "threshold_queue_age_seconds" {
  description = <<-EOT
    How old the oldest unprocessed event may get. 900s (15 minutes).

    Chosen against the agent's own cadence: it uploads every 30 seconds and the
    rollup refreshes every 2 minutes, so a queue holding something for a quarter
    of an hour means the worker is not keeping up or is not running. Short
    enough to catch a stopped worker before a morning's data is stale; long
    enough that the 9am herd draining does not page anybody.
  EOT
  type        = number
  default     = 900
}

# WHAT COUNTS AS A FATAL LOG LINE. CloudWatch Logs filter patterns, not regex:
# a leading ? makes each term an OR, and matching is case-sensitive.
#
#   panic:          Go's panic, first line, both Go services
#   fatal error:    Go runtime failures - out of memory, deadlock detected
#   FATAL ERROR:    V8, which is how a Node heap-limit death announces itself
#   UnhandledPromiseRejection   Node, which exits non-zero on these
#
# DELIBERATELY NOT "error" or "Error". Both services log handled errors at
# level error constantly and correctly - a failed upload, a rejected signature.
# Alarming on those would page hourly and be muted within a week. This pattern
# is meant to match only lines a process prints while dying.
variable "log_fatal_pattern" {
  type    = string
  default = "?\"panic: \" ?\"fatal error: \" ?\"FATAL ERROR\" ?\"UnhandledPromiseRejection\""
}
