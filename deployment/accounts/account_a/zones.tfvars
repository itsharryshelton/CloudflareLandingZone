# Account: account_a - zones.
#
# Identity only: logical key => domain name. Passed to EVERY layer. So you only need to reference "primary" instead of your domain.
# Keys are permanent. Renaming one destroys and recreates the zone in the zones. Don't change unless you fancy remaking it fully.
#
# Zone configuration (settings, DNS records) lives in dns.tfvars, not here - the waf and load_balancing layers do not require seeing DNS records.

zones = {
  primary = {
    domain_name = "example.com"
    zone_tier   = "business"
  }

  mail = {
    domain_name = "example.org"
    # No zone_tier, so this zone falls back to default_zone_tier ("free").
  }
}
