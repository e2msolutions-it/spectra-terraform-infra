variable "name" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ecs_security_group_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.large"
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
