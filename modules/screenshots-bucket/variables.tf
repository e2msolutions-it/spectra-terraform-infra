variable "name" {
  description = "Prefix, e.g. spectra-prod-01."
  type        = string
}

variable "kms_key_arn" {
  type = string
}

variable "enable_ia_transition" {
  description = <<-EOT
    OFF by default, and that is deliberate. Spectra screenshots are ~40-80 KB
    stitched WebP frames, and S3 makes Standard-IA a losing trade at that size:

      * Lifecycle transitions SKIP objects under 128 KB by default, so the rule
        would silently do nothing at all.
      * Standard-IA has a 128 KB MINIMUM BILLABLE object size. A 60 KB frame is
        billed as 128 KB - roughly 2.1x its real bytes. IA is ~$0.0125/GB against
        Standard's ~$0.023/GB, so 2.1x the billed volume at 0.54x the rate costs
        MORE than simply leaving it in Standard.
      * Lifecycle transitions are charged PER OBJECT. At millions of frames a
        month that request bill dwarfs any storage saving.
      * Standard-IA also bills a 30-day minimum duration, which collides with a
        short expiry.

    Only enable this if frames become substantially larger than 128 KB.
  EOT
  type        = bool
  default     = false
}

variable "ia_days" {
  description = "Only used when enable_ia_transition = true."
  type        = number
  default     = 30
}

variable "expire_days" {
  description = "Hard delete after this many days - this is what enforces the ~6-month retention window."
  type        = number
  default     = 180
}

variable "transition_default_minimum_object_size" {
  description = <<-EOT
    Set EXPLICITLY so it stops appearing as a phantom plan change. AWS applies a
    128 KB default minimum for lifecycle transitions (since Sept 2024) and the
    provider now manages this attribute, so leaving it unset shows a diff on
    every plan.
      all_storage_classes_128K - AWS default; skip objects under 128 KB
      varies_by_storage_class  - allow sub-128 KB objects to transition
  EOT
  type        = string
  default     = "all_storage_classes_128K"
}
