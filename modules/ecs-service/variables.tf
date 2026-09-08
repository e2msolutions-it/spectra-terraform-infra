variable "name" {
  description = "Service name, e.g. spectra-stag-01-agent-api."
  type        = string
}

variable "cluster_arn" {
  type = string
}

variable "capacity_provider_name" {
  type = string
}

variable "image" {
  description = "Full image reference INCLUDING an immutable tag. Never use :latest - ECR repos here are IMMUTABLE, so :latest can never be re-pushed and a service would silently keep the old image forever."
  type        = string
}

variable "task_role_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "region" {
  description = "Used for the awslogs driver."
  type        = string
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "container_port" {
  description = "Port the process listens on. Ignored when attach_to_alb = false."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "CPU units reserved (1024 = 1 vCPU). A t4g.small has 2048 total."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Hard memory limit in MiB - the container is killed above this."
  type        = number
  default     = 448
}

variable "memory_reservation" {
  description = "Soft limit used for bin-packing; the container may burst to `memory`."
  type        = number
  default     = 256
}

variable "environment" {
  description = "Plain environment variables. NEVER put secrets here - they are visible in the task definition."
  type        = map(string)
  default     = {}
}

variable "command" {
  description = "Override the image entrypoint args (empty = image default)."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "enable_execute_command" {
  description = "ECS Exec (shell into a running task). Requires ssmmessages:* on the TASK role, so leave false until those are added."
  type        = bool
  default     = false
}

# ---- Load balancer attachment (omit entirely for the worker) ----
variable "attach_to_alb" {
  type    = bool
  default = false
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "listener_arn" {
  description = "HTTPS listener on the shared ALB to attach a host-based rule to."
  type        = string
  default     = ""
}

variable "host_header" {
  description = "Hostname this service answers, e.g. spectra-api.e2msolutions.net."
  type        = string
  default     = ""
}

variable "rule_priority" {
  description = "Listener rule priority. Reserved ranges: prod 100-199, staging 200-299 (apex redirect uses 900)."
  type        = number
  default     = 100
}

variable "health_check_path" {
  type    = string
  default = "/healthz"
}

variable "health_check_grace_period_seconds" {
  description = "Grace before the ALB can kill a starting task - must exceed cold start (DB pool + Secrets Manager fetch)."
  type        = number
  default     = 60
}

variable "deregistration_delay" {
  description = "Kept short: these are stateless request handlers, so deploys drain fast."
  type        = number
  default     = 30
}
