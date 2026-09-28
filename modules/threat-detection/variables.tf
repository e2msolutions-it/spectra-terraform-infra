variable "name" {
  description = "Prefix, e.g. spectra. Buckets become <name>-cloudtrail-<account_id>."
  type        = string
}

variable "kms_key_arn" {
  description = "Shared CMK encrypting the findings SNS topic."
  type        = string
}

variable "alert_emails" {
  description = <<-EOT
    Where security findings are sent.

    EACH ADDRESS MUST CONFIRM BY EMAIL. AWS sends a subscription confirmation
    link and delivers nothing until somebody clicks it. Terraform reports the
    subscription as created regardless, so "applied successfully" does not mean
    "alerts are arriving" - check the inbox after the first apply.

    AN EMPTY LIST IS ACCEPTED AND IS ALMOST CERTAINLY A MISTAKE. The detection
    services still run and findings still land in their consoles, but nothing
    reaches a person, which is the failure this module exists to prevent. It is
    not a hard error only because there are legitimate orders of operations -
    enabling detection first, deciding the distribution list second.

    A PagerDuty or Slack integration URL can replace this later by changing the
    subscription protocol to https; the topic and every rule pointing at it
    stay exactly as they are.
  EOT
  type        = list(string)
  default     = []
}

variable "enable_guardduty" {
  description = <<-EOT
    GuardDuty: ~$3-6/month at this account's volume, priced on the CloudTrail
    events, VPC flow logs and DNS queries it analyses.

    The highest value per dollar of the three services here, because it is the
    only one that detects BEHAVIOUR rather than configuration - credentials
    used from an unexpected location, an instance talking to a known-bad host,
    S3 objects being enumerated in a way nothing legitimate does.
  EOT
  type        = bool
  default     = true
}

variable "guardduty_min_severity" {
  description = <<-EOT
    Findings at or above this severity are emailed. GuardDuty's scale runs
    0.1-8.9: LOW below 4, MEDIUM 4-6.9, HIGH 7 and above.

    4 (medium) on purpose. Low findings are dominated by internet background
    noise - port scans against the ALB - which arrive constantly and mean
    nothing individually. Emailing them trains people to ignore the address,
    and an ignored alert channel is worse than none. Everything is still in the
    console regardless.
  EOT
  type        = number
  default     = 4
}

variable "enable_cloudtrail" {
  description = <<-EOT
    A durable multi-region trail, management events only: ~$1/month, which is
    S3 storage. The first management-events trail per account is free.

    CloudTrail Event history already exists without this and keeps 90 days. A
    trail adds the three things that matter: it survives somebody turning
    Event history off, it writes to a bucket with its own policy, and it keeps
    longer than 90 days. It is also what GuardDuty reads.
  EOT
  type        = bool
  default     = true
}

variable "cloudtrail_retention_days" {
  description = <<-EOT
    365, chosen against the other clocks in this system rather than out of the
    air: audit_log keeps 24 months, activity data 6. Account-level "who changed
    what in AWS" sits between those - long enough to investigate something
    noticed late, short enough that the bucket stays trivial.
  EOT
  type        = number
  default     = 365
}

variable "enable_config" {
  description = <<-EOT
    OFF BY DEFAULT, deliberately, and this is the one to argue about.

    AWS Config costs ~$10-20/month at this account size - $0.003 per
    configuration item recorded plus rule evaluations - which is an order of
    magnitude more than GuardDuty and CloudTrail combined. This tree rejected
    interface VPC endpoints at ~$7/month each, so it cannot wave that away.

    It is also the least aligned with what was asked for. Config detects
    CONFIGURATION DRIFT, not threats: it tells you a bucket became public, not
    that someone is using your credentials from another continent. Useful, but
    a different question.

    TURN IT ON WHEN the driver is evidence rather than detection - a customer
    security review or a DPDP audit asking to see continuous configuration
    monitoring. It is one line, and the four rules that matter here are already
    written.
  EOT
  type        = bool
  default     = false
}
