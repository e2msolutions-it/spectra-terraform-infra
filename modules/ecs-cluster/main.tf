# Per-env ECS-on-EC2 cluster. Runs on arm64 (Graviton / t4g) by default — the
# AMI is selected to MATCH var.architecture so the launch template can never
# drift (an x86_64 AMI under an arm64 instance type is what breaks the ASG).
locals {
  ecs_ami_ssm = {
    x86_64 = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
    arm64  = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
  }
}

data "aws_ssm_parameter" "ecs_ami" {
  name = local.ecs_ami_ssm[var.architecture]
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-ecs-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "instance_ecs" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-ecs-instance-profile"
  role = aws_iam_role.instance.name
}

resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.name}-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type
  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }
  vpc_security_group_ids = [var.ecs_security_group_id]
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  monitoring {
    enabled = true
  }
  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.this.name}" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
  USERDATA
  )
  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-ecs-instance" }
  }
}

resource "aws_autoscaling_group" "ecs" {
  name                  = "${var.name}-ecs-asg"
  vpc_zone_identifier   = var.private_subnet_ids
  min_size              = var.min_size
  max_size              = var.max_size
  desired_capacity      = var.desired_capacity
  protect_from_scale_in = true
  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }
  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }
  tag {
    key                 = "Name"
    value               = "${var.name}-ecs-instance"
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "this" {
  name = "${var.name}-cp"
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"
    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]
  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
    base              = 1
  }
}
