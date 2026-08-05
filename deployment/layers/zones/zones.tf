# Zones, their secure baseline of settings, and their DNS records.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/zone_base?ref=v1.0.0"
module "zones" {
  source = "../../../modules/zone_base"

  for_each = local.zones

  account_id  = var.cloudflare_account_id
  domain_name = each.value.domain_name

  zone_type = each.value.zone_type
  paused    = each.value.paused

  ssl_mode        = each.value.ssl_mode
  min_tls_version = each.value.min_tls_version
  zone_settings   = each.value.zone_settings

  dns_records = each.value.dns_records
}
