name               = "spectra-global-network"
region             = "us-east-1"
vpc_cidr           = "10.40.0.0/16"
az_count           = 2
single_nat_gateway = true
waf_rate_limit     = 3000

# E2M office egress, exempt from the per-IP WAF rate rule ONLY. That rule
# counts an entire office as one machine and blocks the whole site at ~240
# monitored machines behind one address; these addresses still face the
# per-device limit in agent-api, and every other WAF rule still applies.
waf_rate_limit_exempt_ips = ["14.194.54.150/32"]
