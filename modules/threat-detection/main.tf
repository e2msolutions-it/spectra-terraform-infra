# Account-level threat detection: GuardDuty, a durable CloudTrail, optional
# AWS Config, and somewhere for findings to actually arrive.
#
# WHY ALERTING IS THE POINT AND THE SERVICES ARE THE EASY PART. Turning on
# GuardDuty is one resource. The failure mode it invites is a console nobody
# opens: findings accumulate, the compliance box is ticked, and the first
# anybody hears of a problem is from somewhere else entirely. So every path
# here ends at an email address, and nothing is enabled that does not have one.
#
# PAGERDUTY IS NOT THE ROUTE, TODAY. The observability workspace has PagerDuty
# services defined, but escalation_user_ids is still commented out in its
# tfvars - so an alert sent there would page nobody. SNS with an email
# subscription is not elegant, it just works, and it can be pointed at a
# PagerDuty integration URL later by changing one variable. Something that
# arrives beats something well-designed that does not.
#
# ---------------------------------------------------------------------------
# COST, BECAUSE THIS TREE HAS A POSITION ON IT.
#
# Interface VPC endpoints were rejected here at ~$7/month each. That rules out
# handwaving about what security services cost. Rough monthly figures for an
# account this size, us-east-1:
#
#   GuardDuty     ~$3-6    priced on CloudTrail events, VPC flow logs and DNS
#                          volume analysed. Small account, small bill.
#   CloudTrail    ~$1      the first management-events trail per account is
#                          free; this is the S3 storage under it.
#   AWS Config    ~$10-20  $0.003 per configuration item recorded plus rule
#                          evaluations. It is the expensive one BY AN ORDER OF
#                          MAGNITUDE, and it is also the least aligned with the
#                          item that asked for this: Config detects
#                          CONFIGURATION DRIFT, not threats.
#
# So Config defaults to OFF, with a variable to turn it on in one line. That is
# a recommendation, not a refusal - if a customer or DPDP review asks for
# evidence of continuous configuration monitoring, flip enable_config and it is
# there. What is not defensible is paying for it by accident.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Where findings go
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "findings" {
  name              = "${var.name}-security-findings"
  kms_master_key_id = var.kms_key_arn
}

# CONFIRMATION IS MANUAL AND THAT IS NOT A BUG. AWS emails each address a
# confirmation link; until somebody clicks it the subscription is "pending" and
# delivers nothing. Terraform will show it as created either way, so after the
# first apply somebody must check their inbox - see the alert_emails variable.
resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.findings.arn
  protocol  = "email"
  endpoint  = each.value
}

# EventBridge must be allowed to publish, and the KMS key must let it encrypt.
data "aws_iam_policy_document" "topic" {
  statement {
    sid       = "EventBridgePublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.findings.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "findings" {
  arn    = aws_sns_topic.findings.arn
  policy = data.aws_iam_policy_document.topic.json
}

# ---------------------------------------------------------------------------
# GuardDuty
# ---------------------------------------------------------------------------

# ONE DETECTOR PER REGION PER ACCOUNT is an AWS limit, so if GuardDuty was ever
# enabled by hand this apply fails with "detector already exists". That is not
# a reason to import blindly - find out who enabled it and why first.
resource "aws_guardduty_detector" "this" {
  count = var.enable_guardduty ? 1 : 0

  enable = true

  # FIFTEEN MINUTES, NOT SIX HOURS. The default publishing frequency delays a
  # finding by up to six hours, which for "credentials from this instance are
  # being used somewhere else" is the difference between an incident and a
  # breach. The frequency applies to UPDATES of existing findings; a brand new
  # finding is published immediately either way.
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  datasources {
    s3_logs {
      # The screenshots bucket holds pictures of people's screens. S3 data
      # event analysis is what would notice them being enumerated or copied
      # somewhere they should not go.
      enable = true
    }
    kubernetes {
      audit_logs { enable = false } # no EKS in this account
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          # OFF: it is billed per GB scanned and the ECS instances are
          # stateless, rebuilt from an AMI, and hold nothing worth scanning.
          # A compromised one is replaced, not cleaned.
          enable = false
        }
      }
    }
  }
}

# ONLY MEDIUM AND ABOVE REACH A HUMAN. GuardDuty severity runs 0.1-8.9; low
# findings are dominated by things like port scans from the internet, which
# arrive constantly and mean nothing on their own. Routing them to email
# teaches people to ignore the address, which is worse than not sending them.
# Everything is still in the GuardDuty console regardless of this filter.
resource "aws_cloudwatch_event_rule" "guardduty" {
  count = var.enable_guardduty ? 1 : 0

  name        = "${var.name}-guardduty-findings"
  description = "GuardDuty findings at severity ${var.guardduty_min_severity} and above."

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", var.guardduty_min_severity] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty" {
  count = var.enable_guardduty ? 1 : 0

  rule      = aws_cloudwatch_event_rule.guardduty[0].name
  target_id = "sns"
  arn       = aws_sns_topic.findings.arn

  # THE DEFAULT EMAIL IS UNREADABLE. A raw GuardDuty finding is several hundred
  # lines of JSON, and an alert nobody can read at a glance is an alert nobody
  # reads. This renders the four things that decide whether to care, and the
  # console has the rest.
  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      type        = "$.detail.type"
      description = "$.detail.description"
      region      = "$.detail.region"
      account     = "$.detail.accountId"
      time        = "$.time"
    }
    input_template = <<-EOT
      "GuardDuty severity <severity>: <type>"
      ""
      "<description>"
      ""
      "account <account> in <region> at <time>"
      "Console: https://console.aws.amazon.com/guardduty/home?region=<region>#/findings"
    EOT
  }
}

# ---------------------------------------------------------------------------
# CloudTrail
# ---------------------------------------------------------------------------

# WHAT THE CONSOLE ALREADY GIVES YOU, so this is not mistaken for the only
# record: CloudTrail Event history is on by default, covers management events,
# and keeps 90 days. What it does NOT do is survive being turned off, get
# written somewhere an attacker cannot also reach, or keep anything past 90
# days. A trail with its own bucket does.
#
# It is also what GuardDuty analyses, and what an audit asks for when it asks
# who did what in the account.
resource "aws_s3_bucket" "trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = "${var.name}-cloudtrail-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "trail" {
  count                   = var.enable_cloudtrail ? 1 : 0
  bucket                  = aws_s3_bucket.trail[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# SSE-S3, NOT SSE-KMS, and this is the one place in the tree that differs.
# CloudTrail writing to a KMS-encrypted bucket needs the key policy to grant
# cloudtrail.amazonaws.com, and getting that wrong fails silently - the trail
# stops delivering and the only sign is an absence of objects. The audit value
# here is in having the log at all; the objects are already server-side
# encrypted and the bucket is private.
resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id

  transition_default_minimum_object_size = "all_storage_classes_128K"

  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = var.cloudtrail_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "trail_bucket" {
  count = var.enable_cloudtrail ? 1 : 0

  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail[0].arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trail[0].arn, "${aws_s3_bucket.trail[0].arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  policy = data.aws_iam_policy_document.trail_bucket[0].json
}

resource "aws_cloudtrail" "this" {
  count = var.enable_cloudtrail ? 1 : 0

  name                       = "${var.name}-trail"
  s3_bucket_name             = aws_s3_bucket.trail[0].id
  is_multi_region_trail      = true
  include_global_service_events = true
  enable_log_file_validation = true

  # MANAGEMENT EVENTS ONLY. Data events (every S3 object read, every Lambda
  # invoke) would record every screenshot fetch - which sounds useful until you
  # notice the portal ALREADY records exactly that in audit_log, with the name
  # of the person who looked, which CloudTrail cannot know because every read
  # arrives as the same task role. Paying per-event for a worse version of a
  # record you already keep is not a trade worth making.

  depends_on = [aws_s3_bucket_policy.trail]
}

# ---------------------------------------------------------------------------
# AWS Config — off by default. See the cost note at the top of this file.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "config" {
  count  = var.enable_config ? 1 : 0
  bucket = "${var.name}-awsconfig-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "config" {
  count                   = var.enable_config ? 1 : 0
  bucket                  = aws_s3_bucket.config[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "config_assume" {
  count = var.enable_config ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  count              = var.enable_config ? 1 : 0
  name               = "${var.name}-awsconfig"
  assume_role_policy = data.aws_iam_policy_document.config_assume[0].json
}

resource "aws_iam_role_policy_attachment" "config" {
  count      = var.enable_config ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

data "aws_iam_policy_document" "config_bucket" {
  count = var.enable_config ? 1 : 0
  statement {
    sid       = "ConfigWrite"
    actions   = ["s3:PutObject", "s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config[0].arn, "${aws_s3_bucket.config[0].arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  count  = var.enable_config ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  policy = data.aws_iam_policy_document.config_bucket[0].json
}

resource "aws_config_configuration_recorder" "this" {
  count    = var.enable_config ? 1 : 0
  name     = "${var.name}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  count          = var.enable_config ? 1 : 0
  name           = "${var.name}-delivery"
  s3_bucket_name = aws_s3_bucket.config[0].id
  depends_on     = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  count      = var.enable_config ? 1 : 0
  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}

# A DELIBERATELY SHORT LIST. Config bills per rule evaluation, and a hundred
# rules nobody reads costs money to produce noise. These four are the ones that
# would actually matter here, given what this account holds:
#
#   s3-bucket-public-read-prohibited   the screenshots bucket
#   s3-bucket-ssl-requests-only        every bucket has this policy; catch a drift
#   rds-instance-public-access-check   the database is private and must stay so
#   iam-root-access-key-check          root must never have an access key
resource "aws_config_config_rule" "managed" {
  for_each = var.enable_config ? toset([
    "S3_BUCKET_PUBLIC_READ_PROHIBITED",
    "S3_BUCKET_SSL_REQUESTS_ONLY",
    "RDS_INSTANCE_PUBLIC_ACCESS_CHECK",
    "IAM_ROOT_ACCESS_KEY_CHECK",
  ]) : toset([])

  name = lower(replace(each.value, "_", "-"))
  source {
    owner             = "AWS"
    source_identifier = each.value
  }
  depends_on = [aws_config_configuration_recorder_status.this]
}

resource "aws_cloudwatch_event_rule" "config" {
  count = var.enable_config ? 1 : 0

  name        = "${var.name}-config-noncompliant"
  description = "An AWS Config rule moved to NON_COMPLIANT."

  event_pattern = jsonencode({
    source        = ["aws.config"]
    "detail-type" = ["Config Rules Compliance Change"]
    detail = {
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "config" {
  count = var.enable_config ? 1 : 0

  rule      = aws_cloudwatch_event_rule.config[0].name
  target_id = "sns"
  arn       = aws_sns_topic.findings.arn

  input_transformer {
    input_paths = {
      rule     = "$.detail.configRuleName"
      resource = "$.detail.resourceId"
      type     = "$.detail.resourceType"
      region   = "$.detail.awsRegion"
      time     = "$.time"
    }
    input_template = <<-EOT
      "AWS Config: <rule> is NON_COMPLIANT"
      ""
      "resource <resource> (<type>) in <region> at <time>"
    EOT
  }
}
