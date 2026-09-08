environment = "staging"
instance    = "spectra-stag-01"
region      = "us-east-1"
db_name     = "spectra_stag"

# Live hostnames (Route53 + wildcard ACM cert on the shared ALB):
domain_agent  = "spectra-api-stag.e2msolutions.net"
domain_portal = "spectra-stag.e2msolutions.net"

# Per-env compute sizing — staging runs smaller than prod (arm64 / Graviton):
instance_type        = "t4g.small"
ecs_min_size         = 1
ecs_max_size         = 3
ecs_desired_capacity = 1

# Scalr remote-state sharing (point at your Scalr account + global env):
scalr_hostname    = "e2msolutions.scalr.io"
scalr_environment = "env-v0o989ah28npjf8t6"
network_workspace = "spectra-global-network"
data_workspace    = "spectra-global-data"

# ---- CI/CD (set these to your actual GitHub repos) ----
api_repository_id    = "e2msolutions-it/spectra-agent-api"
portal_repository_id = "e2msolutions-it/spectra-portal"
pipeline_branch      = "stag"
