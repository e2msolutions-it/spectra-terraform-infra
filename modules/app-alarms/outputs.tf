output "topic_arn" {
  description = "Point anything else that should page this environment at this topic."
  value       = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  description = "Every alarm created, so a plan can be read against what was intended."
  value = sort(concat(
    [for a in aws_cloudwatch_metric_alarm.target_5xx : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.unhealthy_hosts : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.cpu_high : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.memory_high : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.tasks_below_desired : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.fatal : a.alarm_name],
    [aws_cloudwatch_metric_alarm.queue_backlog.alarm_name],
    [aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_name],
  ))
}

# Not an alarm - an EventBridge rule - so it is named separately rather than
# folded into the list above and quietly mistaken for one.
output "task_stopped_rule_name" {
  description = "The rule that reports a task stopping for a reason that is not a deployment."
  value       = aws_cloudwatch_event_rule.task_stopped.name
}

# Stated as an output because the failure is silent: alarms exist, fire, and
# reach nobody.
output "paging_enabled" {
  value = var.pagerduty_integration_url != ""
}
