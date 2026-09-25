variable "name" {
  description = "Cell name, e.g. spectra-stag-01. Bucket becomes <name>-audit-vault-<account_id>."
  type        = string
}

variable "kms_key_arn" {
  description = "Shared CMK for SSE-KMS."
  type        = string
}

variable "object_lock_mode" {
  description = <<-EOT
    COMPLIANCE or GOVERNANCE.

    COMPLIANCE is the only value that does the job this bucket exists for: no
    principal can delete or shorten retention before it expires, including the
    account root and AWS support. GOVERNANCE lets anyone holding
    s3:BypassGovernanceRetention override it, which is the privileged insider
    this is meant to defend against - so it protects against accident and not
    against intent.

    It is here as a variable rather than hardcoded because it is a decision
    somebody should be able to see and argue with, not because switching it is
    expected.
  EOT
  type        = string
  default     = "COMPLIANCE"

  validation {
    condition     = contains(["COMPLIANCE", "GOVERNANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be COMPLIANCE or GOVERNANCE."
  }
}

variable "default_retention_days" {
  description = <<-EOT
    How long an object cannot be deleted for.

    STARTING SHORT ON PURPOSE. audit_log itself is kept 24 months
    (spectra_prune_audit), and matching that here is where this should end up.
    But COMPLIANCE mode is a one-way door per object: if the writer has a bug
    and seals nonsense, that nonsense is undeletable for the full window. 90
    days is long enough to prove the pipeline writes what it should and short
    enough that a mistake ages out inside a quarter.

    RAISING THIS LATER ONLY AFFECTS OBJECTS WRITTEN AFTERWARDS. Retention can
    be extended on a locked object but never shortened, and the default applies
    at write time - so objects sealed during the 90-day period keep their
    90-day clock. The log will therefore have a window at the start where the
    vault copy expires before the database copy does. That gap is real and
    should be written down wherever the retention basis is documented, not
    quietly forgotten when this number goes up.
  EOT
  type        = number
  default     = 90

  validation {
    # One day would technically work and would be a lie - a vault whose
    # contents evaporate before anybody asks a question is not a vault.
    condition     = var.default_retention_days >= 30
    error_message = "default_retention_days must be at least 30; anything shorter cannot answer a question asked after the fact."
  }
}
