# Account: account_a - DNS configuration.  Consumed by the dns layer only.
#
#   terraform -chdir=layers/dns plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/dns.tfvars
#
# Keys must match zones.tfvars
#
# Reminder: proxied = true needs ttl = 1 and only works on A/AAAA/CNAME. Names may
# be "@", relative, or fully-qualified - the module qualifies them either way, so
# "www" and "www.example.com" are the same record and declaring both fails.

dns_config = {
  primary = {
    dns_records = [
      { name = "@", type = "A", content = "203.0.113.10", ttl = 1, proxied = true },
      { name = "www", type = "CNAME", content = "example.com", ttl = 1, proxied = true },
      { name = "@", type = "MX", content = "mx.example.net", ttl = 3600, priority = 10 },
      { name = "@", type = "TXT", content = "v=spf1 include:example.net -all", ttl = 3600 },

      # Delegating a signed child zone to another DNS provider: the NS records
      # hand dev.example.com over, and the DS record (taken from that provider)
      # extends the chain of trust down from this zone, which needs DNSSEC on.
      # Content is "<key tag> <algorithm> <digest type> <digest>". The values
      # here are placeholders.
      { name = "dev", type = "NS", content = "ns1.example.net", ttl = 3600 },
      { name = "dev", type = "NS", content = "ns2.example.net", ttl = 3600 },
      { name = "dev", type = "DS", content = "12345 13 2 3B9F1A6C0E5D4B2A8F7C6E1D0A9B8C7D6E5F4A3B2C1D0E9F8A7B6C5D4E3F2A1B", ttl = 3600 },
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
  test_domain = {
    dns_records = [
      { name = "@", type = "A", content = "233.0.113.10", ttl = 1, proxied = true },
      { name = "www", type = "CNAME", content = "example.com", ttl = 1, proxied = true },
      { name = "@", type = "MX", content = "mx.example.net", ttl = 3600, priority = 10 },
      { name = "@", type = "TXT", content = "v=spf1 include:example.net -all", ttl = 3600 },
    ]
  }
}
