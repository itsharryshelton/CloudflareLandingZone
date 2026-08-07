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

  ssl_mode         = each.value.ssl_mode
  min_tls_version  = each.value.min_tls_version
  tls_1_3          = each.value.tls_1_3
  always_use_https = each.value.always_use_https
  zone_settings    = each.value.zone_settings

  dns_records = each.value.dns_records
}

# Zone tier and zone-level bot posture.
#
# Split from zone_base rather than folded into it because these are the two
# things that can cost money or change plan entitlement, and keeping them in
# their own module keeps that reviewable. Per-category bot rules
# (Search / Agent / Training) are NOT here: Cloudflare allows one entry-point
# ruleset per phase per zone, the waf layer owns http_request_firewall_custom,
# so they are configured as `bot_traffic` on a waf policy.
module "zone_rules" {
  source = "../../../modules/zone_rules"

  for_each = local.zones

  zone_id   = module.zones[each.key].zone_id
  zone_tier = each.value.zone_tier

  manage_subscription    = each.value.manage_subscription
  subscription_frequency = var.default_subscription_frequency

  bot_management = each.value.bot_management
}
