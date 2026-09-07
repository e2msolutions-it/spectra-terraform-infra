environment = "staging"
instance    = "spectra-stag-01"
region      = "us-east-1"
db_name     = "spectra_stag"

# Set once DNS is ready (Phase 1 provisions ACM + HTTPS):
domain_agent  = ""
domain_portal = ""

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
