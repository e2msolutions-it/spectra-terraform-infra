variable "name" {
  type = string
}

variable "repositories" {
  description = "Service image repositories (shared across environments; tag per release)."
  type        = list(string)
  default     = ["agent-api", "portal", "core-api", "worker"]
}
