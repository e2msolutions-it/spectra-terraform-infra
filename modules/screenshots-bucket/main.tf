# Per-environment screenshots bucket. Buckets have no standing cost, so each
# environment gets its own for clean data isolation even in the shared model.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  bucket = "${var.name}-screenshots-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Explicit so it stops surfacing as a phantom diff on every plan: AWS now
  # manages this attribute and defaults it to the 128 KB behaviour.
  transition_default_minimum_object_size = var.transition_default_minimum_object_size

  rule {
    id     = "expire"
    status = "Enabled"
    filter {}

    # NO IA transition by default: at ~40-80 KB per frame it is either skipped
    # outright (128 KB minimum) or costs MORE than Standard once the 128 KB
    # minimum BILLABLE size and per-object transition requests are counted.
    # See enable_ia_transition for the full reasoning.
    dynamic "transition" {
      for_each = var.enable_ia_transition ? [1] : []
      content {
        days          = var.ia_days
        storage_class = "STANDARD_IA"
      }
    }

    # This is the rule that actually matters: it enforces the retention window.
    expiration {
      days = var.expire_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
