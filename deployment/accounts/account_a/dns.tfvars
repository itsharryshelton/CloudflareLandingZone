# Account: account_a - zone configuration. Consumed by the zones layer only.
#
#   terraform -chdir=layers/zones plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/dns.tfvars
#
# Keys must match zones.tfvars. A key with no matching zone fails the plan rather than silently deploying a zone with no records
#
# Reminder: proxied = true needs ttl = 1 and only works on A/AAAA/CNAME. Names may
# be "@", relative, or fully-qualified - the module qualifies them either way, so
# "www" and "www.example.com" are the same record and declaring both fails.

zone_config = {
  primary = {
    dns_records = [
      { name = "@", type = "A", content = "203.0.113.10", ttl = 1, proxied = true },
      { name = "www", type = "CNAME", content = "example.com", ttl = 1, proxied = true },
      { name = "@", type = "MX", content = "mx.example.net", ttl = 3600, priority = 10 },
      { name = "@", type = "TXT", content = "v=spf1 include:example.net -all", ttl = 3600 },
    ]
  }

  mail = {
    dns_records = [
      { name = "@", type = "MX", content = "mx1.example.net", ttl = 3600, priority = 10 },
      { name = "@", type = "MX", content = "mx2.example.net", ttl = 3600, priority = 20 },
      { name = "@", type = "TXT", content = "v=spf1 include:example.net -all", ttl = 3600 },
      { name = "_dmarc", type = "TXT", content = "v=DMARC1; p=reject; rua=mailto:dmarc@example.net", ttl = 3600 },
    ]
  }
}
