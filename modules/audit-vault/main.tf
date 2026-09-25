# Per-environment audit vault: a WORM copy of the audit log.
#
# WHAT THIS DEFENDS AGAINST, and it is a specific thing. audit_log lives in the
# same Postgres the portal reads. Migration 0014 removed DELETE and UPDATE from
# the application role, which stops the portal and anyone holding the portal's
# IAM token - but the RDS master still owns the table and can still delete
# anything. Nothing inside one database can defend that database against its
# own owner. The defence has to be a copy somewhere the owner cannot reach.
#
# Object Lock in COMPLIANCE mode is that somewhere: an object cannot be deleted
# or overwritten until its retention expires, by anyone. Not an administrator,
# not the account root, not AWS support. That is the entire product here, and
# it is why GOVERNANCE mode would be pointless: a principal holding
# s3:BypassGovernanceRetention could override it, and the threat model is
# precisely a privileged insider.
#
# TAMPER-EVIDENT, NOT TAMPER-PROOF, and the distinction is the name of the
# feature. This does not stop somebody deleting rows from Postgres. It makes
# the deletion VISIBLE: the sealed copy still carries the event, so comparing
# the two shows the gap. Each object also carries the sha256 of the one before
# it in its org's chain (see agent-api migration 0014), so the objects verify
# each other with this bucket's own listing and nothing else - no database, no
# ledger, no trust in the writer.
#
# ---------------------------------------------------------------------------
# OBJECT LOCK CAN ONLY BE TURNED ON WHEN THE BUCKET IS CREATED.
#
# It requires versioning and is not something Terraform can add to an existing
# bucket - `object_lock_enabled` on aws_s3_bucket forces replacement. So this
# is a new bucket rather than a prefix inside an existing one, and destroying
# it once it holds locked objects is not possible until every object's
# retention has expired. Treat `terraform destroy` on this module as
# unavailable for the length of the retention window. That is not a bug; it is
# what was bought.
#
# ---------------------------------------------------------------------------
# NO LIFECYCLE EXPIRY RULE, deliberately, unlike the screenshots bucket.
#
# An expiry rule and an Object Lock retention are different clocks, and a
# bucket with both invites the reading that objects vanish on the shorter one.
# They do not - a lifecycle expiration cannot remove a locked object - so the
# rule would be decoration that quietly misleads whoever reads this file next.
# Retention is stated in exactly one place: default_retention_days below.
#
# Volume makes this affordable: an audit row is a few hundred bytes, so at this
# fleet's rate the whole vault is single-digit megabytes a year. Storage that
# cannot be deleted is only frightening when it is large.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  bucket = "${var.name}-audit-vault-${data.aws_caller_identity.current.account_id}"

  # Create-only. See the note above: this cannot be added later, and changing
  # it replaces the bucket - which, once objects are locked, will fail.
  object_lock_enabled = true

  # A guard rail, not a belief that this bucket is precious beyond reason: an
  # accidental `terraform destroy` against a vault holding locked objects would
  # fail partway and leave a confusing half-state. Better to refuse in the plan.
  lifecycle {
    prevent_destroy = true
  }
}

# Object Lock REQUIRES versioning, and this is the reason it is written out
# rather than left implicit: a delete against a versioned bucket writes a
# delete marker instead of removing anything, and the locked version stays
# retrievable underneath it. So even the appearance of a deletion is
# recoverable, which is a second layer under the lock itself.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
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

# THE DEFAULT RETENTION, applied to every object that arrives without one of
# its own. The writer does not set a per-object retention, so this is the only
# thing standing between a sealed audit record and an administrator who wants
# it gone.
#
# RETENTION CAN BE EXTENDED BUT NEVER SHORTENED. Raising this number affects
# objects written afterwards; it does not reach back. So starting short and
# raising it later leaves the early objects expiring sooner than the log they
# mirror - an honest gap that has to be documented rather than assumed away.
resource "aws_s3_bucket_object_lock_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.default_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# TLS-only, the same posture as every other bucket here. Note what is NOT in
# this policy: nothing grants read access. Who may read the vault is decided
# entirely by IAM, and today the answer is nobody except whoever is holding
# administrator credentials and looking deliberately. The worker can write and
# cannot read; see the writer policy in modules/task-iam.
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
