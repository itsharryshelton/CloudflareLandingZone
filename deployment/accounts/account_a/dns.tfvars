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
    # TLS posture. Omitted fields fall back to the platform defaults
    ssl_mode         = "strict"
    min_tls_version  = "1.2"
    tls_1_3          = "on"
    always_use_https = "on"

    # Zone-level bot posture. This zone is on the business tier (see
    # zones.tfvars), which is what allows sbfm_likely_automated here - setting it
    # on a Free zone fails the plan rather than the apply.
    #
    # These are the coarse controls. Per-category Search / Agent / Training
    # handling is in waf.tfvars, because Cloudflare allows one entry-point
    # ruleset per phase per zone and the waf layer owns that phase.
    #
    # ai_bots_protection is the one that reaches crawlers which do NOT identify
    # themselves; the per-category WAF rules only ever see verified bots.
    bot_management = {
      sbfm_definitely_automated       = "block"
      sbfm_likely_automated           = "managed_challenge"
      sbfm_verified_bots              = "allow"
      sbfm_static_resource_protection = false

      ai_bots_protection = "block"
      crawler_protection = "enabled"
    }

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
