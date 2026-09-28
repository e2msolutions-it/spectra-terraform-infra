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
    [aws_cloudwatch_metric_alarm.queue_backlog.alarm_name],
    [aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_name],
  ))
}

# Stated as an output because the failure is silent: alarms exist, fire, and
# reach nobody.
output "paging_enabled" {
  value = var.pagerduty_integration_url != ""
}
