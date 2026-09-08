environment = "prod"
instance    = "spectra-prod-01"
region      = "us-east-1"
db_name     = "spectra_prod"

# Live hostnames (Route53 + wildcard ACM cert on the shared ALB):
domain_agent  = "spectra-api.e2msolutions.net"
domain_portal = "spectra.e2msolutions.net"

# Per-env compute sizing (isolated cluster/ASG, arm64 / Graviton):
instance_type        = "t4g.small"
ecs_min_size         = 2
ecs_max_size         = 6
ecs_desired_capacity = 2

# Scalr remote-state sharing (point at your Scalr account + global env):
scalr_hostname    = "e2msolutions.scalr.io"
scalr_environment = "env-v0o989ah28npjf8t6"
network_workspace = "spectra-global-network"
data_workspace    = "spectra-global-data"

# ---- CI/CD (set these to your actual GitHub repos) ----
api_repository_id    = "e2msolutions-it/spectra-agent-api"
portal_repository_id = "e2msolutions-it/spectra-portal"
pipeline_branch      = "main"
