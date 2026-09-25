variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "waf_rate_limit" {
  description = <<-EOT
    Requests per 5 minutes PER SOURCE IP before the WAF blocks. Not per device -
    the earlier wording said "per device/IP" and that was wrong in a way that
    matters, because one office is one NAT IP for every machine in it.

    THE ARITHMETIC, measured: an agent makes ~12.5 requests per 5 minutes
    (a 30-second upload tick plus a screenshot upload-URL every 2 minutes), so
    3000 is reached at about 240 MACHINES BEHIND ONE PUBLIC IP. Above that the
    whole site is blocked at once, which presents as every agent in that office
    failing simultaneously. This project is sized for 400-500 machines.

    So this stays as a blunt anti-flood control for the open internet, and the
    offices that would otherwise trip it are listed in
    waf_rate_limit_exempt_ips below. The real per-machine ceiling lives in
    agent-api, which can tell devices apart; see internal/api rateCheck.
  EOT
  type        = number
  default     = 3000
}

variable "waf_rate_limit_exempt_ips" {
  description = <<-EOT
    Corporate egress CIDRs exempt from the per-IP rate rule.

    Empty by default, and an empty list means no IP set is created and the rule
    is exactly as it was - so this is inert until somebody adds an office.

    WHAT THIS DOES NOT WEAKEN: an exempt office still faces the per-device limit
    in agent-api, which is the control that can actually distinguish one
    malfunctioning machine from forty working ones. Exempting the IP removes a
    check that could only ever have fired on the whole site at once.

    Every other WAF rule still applies to these addresses - the managed common
    rule set, and anything added later. Only the rate rule is scoped down.
  EOT
  type        = list(string)
  default     = []
}
