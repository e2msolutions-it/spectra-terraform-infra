environment = "staging"
instance    = "spectra-stag-01"
region      = "us-east-1"
db_name     = "spectra_stag"

# Set once DNS is ready (Phase 1 provisions ACM + HTTPS):
domain_agent  = ""
domain_portal = ""

# Per-env compute sizing — staging runs smaller than prod:
instance_type        = "t3.large"
ecs_min_size         = 1
ecs_max_size         = 3
ecs_desired_capacity = 1

# Scalr remote-state sharing (point at your Scalr account + global env):
scalr_hostname    = "example.scalr.io"
scalr_environment = "spectra-global"
network_workspace = "global-network"
data_workspace    = "global-data"
