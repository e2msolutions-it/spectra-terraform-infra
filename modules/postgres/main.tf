# Single shared PostgreSQL instance. Prod and staging are separated into
# distinct logical databases + least-privilege roles inside this one instance
# (created by the global/data root via the postgresql provider).
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.name}-db-subnets" }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-pg"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name                       = "spectra"
  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false

  # Allow apps (ECS tasks) to auth with short-lived IAM tokens instead of a password.
  iam_database_authentication_enabled = true

  backup_retention_period   = 14
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-pg-final"

  performance_insights_enabled = true
  auto_minor_version_upgrade   = true
  apply_immediately            = true
  backup_window                       = "18:00-18:30"         # Updated backup window to 18:00-18:30 UTC
  maintenance_window                  = "tue:18:45-tue:19:15" # Adjusted maintenance window to follow backup window
  enabled_cloudwatch_logs_exports     = ["iam-db-auth-error"]
  tags = { Name = "${var.name}-pg" }
}
