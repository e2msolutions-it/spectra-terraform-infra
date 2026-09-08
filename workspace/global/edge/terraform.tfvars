name              = "spectra-global-edge"
region            = "us-east-1"
scalr_hostname    = "e2msolutions.scalr.io"
scalr_environment = "env-v0o989ah28npjf8t6"
network_workspace = "spectra-global-network"

# ---- DNS / TLS ----
# e2msolutions.net is hosted in Route53 (this account). Apex + www are 301'd to
# the marketing site, so every subdomain is free for Spectra.
domain_name    = "e2msolutions.net"
create_zone    = true
marketing_host = "www.e2msolutions.com"
redirect_apex  = true

alb_hostnames = ["spectra", "spectra-api", "spectra-stag", "spectra-api-stag"]

# STEP 1: apply with false, set the NS records at the registrar.
# STEP 2: flip to true and re-apply.
dns_delegated = true
