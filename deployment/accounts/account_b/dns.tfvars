# Account: account_b - zone configuration. Consumed by the zones layer only.
#
#   terraform -chdir=layers/zones plan \
#     -var-file=../../accounts/account_b/account.tfvars \
#     -var-file=../../accounts/account_b/zones.tfvars \
#     -var-file=../../accounts/account_b/dns.tfvars
#
# Keys must match zones.tfvars. A key with no matching zone fails the plan rather than silently deploying a zone with no records
#
# Reminder: proxied = true needs ttl = 1 and only works on A/AAAA/CNAME. Names may
# be "@", relative, or fully-qualified - the module qualifies them either way, so
# "www" and "www.example.com" are the same record and declaring both fails.

zone_config = {
  primary = {
    # Example of tuning Security Level of how CF Evaluates Threat Scores / Challenges for inbound traffic.
    zone_settings = {
      security_level = "high"
    }

    dns_records = [
      { name = "@", type = "A", content = "203.0.113.20", ttl = 1, proxied = true },
      { name = "shop", type = "CNAME", content = "example.net", ttl = 1, proxied = true },
    ]
  }
}
