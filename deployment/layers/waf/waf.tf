# Custom firewall rules and rate limiting, per zone.
#
# Rule content comes from local.waf_policies, which concatenates the platform
# baseline catalogue (locals.waf.tf) with any tenant-specific rules. The module
# takes a plain list of rules and knows nothing about baselines or zone keys.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/waf?ref=v1.0.0"
module "waf" {
  source = "../../../modules/waf"

  for_each = local.waf_policies
  zone_id  = data.cloudflare_zone.this[each.value.zone_key].id

  custom_block_rules  = each.value.custom_block_rules
  rate_limiting_rules = each.value.rate_limiting_rules

  custom_ruleset_name = coalesce(
    each.value.custom_ruleset_name,
    "Custom rules - ${var.zones[each.value.zone_key].domain_name}",
  )
  rate_limit_ruleset_name = coalesce(
    each.value.rate_limit_ruleset_name,
    "Rate limiting - ${var.zones[each.value.zone_key].domain_name}",
  )
}
