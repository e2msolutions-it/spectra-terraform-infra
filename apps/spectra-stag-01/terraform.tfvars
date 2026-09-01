environment = "staging"
instance    = "spectra-stag-01"
region      = "ap-south-1"
db_name     = "spectra_stag"

# Set once DNS is ready (Phase 1 provisions ACM + HTTPS):
domain_agent  = ""
domain_portal = ""

# Scalr remote-state sharing (point at your Scalr account + global env):
scalr_hostname    = "example.scalr.io"
scalr_environment = "spectra-global"
network_workspace = "global-network"
data_workspace    = "global-data"
compute_workspace = "global-compute"
