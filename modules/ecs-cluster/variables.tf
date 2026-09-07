variable "name" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ecs_security_group_id" {
  type = string
}

variable "architecture" {
  description = "CPU architecture for the ECS instances AND the AMI. Keep in sync with instance_type (arm64 = t4g/Graviton)."
  type        = string
  default     = "arm64"
  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be \"x86_64\" or \"arm64\"."
  }
}

variable "instance_type" {
  type    = string
  default = "t4g.large"
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 8
}

variable "desired_capacity" {
  type    = number
  default = 2
}
