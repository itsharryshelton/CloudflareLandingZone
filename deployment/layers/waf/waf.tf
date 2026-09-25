# Custom firewall rules, rate limiting and Cloudflare's managed rulesets, per zone.
#
# Rule content comes from local.waf_policies, which concatenates the platform
# baseline catalogue (locals.waf.tf) with any tenant-specific rules. The module
# takes a plain list of rules and knows nothing about baselines or zone keys.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//waf?ref=v1.0.0"
module "waf" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//waf?ref=v1.0.0"

  for_each = local.waf_policies
  zone_id  = data.cloudflare_zone.this[each.value.zone_key].id

  # Bot traffic is emitted by the module ahead of these, into the same ruleset.
  # It cannot live in the zones layer: one entry-point ruleset per phase per zone,
  # and this layer owns http_request_firewall_custom.
  bot_traffic = each.value.bot_traffic

  custom_block_rules  = each.value.custom_block_rules
  rate_limiting_rules = each.value.rate_limiting_rules

  # Cloudflare's own rulesets, in http_request_firewall_managed
  managed_rulesets = each.value.managed_rulesets

  # Skips placed ahead of those rulesets in the same entry point. A skip in
  # custom_block_rules can only drop the whole managed phase.
  managed_exceptions = each.value.managed_exceptions

  custom_ruleset_name = coalesce(
    each.value.custom_ruleset_name,
    "Custom rules - ${var.zones[each.value.zone_key].domain_name}",
  )
  rate_limit_ruleset_name = coalesce(
    each.value.rate_limit_ruleset_name,
    "Rate limiting - ${var.zones[each.value.zone_key].domain_name}",
  )
  managed_ruleset_name = coalesce(
    each.value.managed_ruleset_name,
    "Managed rules - ${var.zones[each.value.zone_key].domain_name}",
  )
}
