# Cache, transform, origin, redirect and configuration rulesets, per zone.
#
# Five modules rather than one, because Cloudflare treats each phase as a
# separate entry-point ruleset with its own schema - and because a zone that
# needs only cache rules should not carry state for the other four.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//cache_rules?ref=v1.0.0"

# http_request_cache_settings. Last matching rule wins in this phase, so the
# order within each policy's cache_rules list is the order of precedence,
# backwards: broad rules first, exceptions after.
module "cache_rules" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//cache_rules"

  for_each = local.cache_policies
  zone_id  = data.cloudflare_zone.this[each.value.zone_key].id

  rules = local.cache_rules_for_module[each.key]

  ruleset_name = coalesce(
    each.value.cache_ruleset_name,
    "Cache rules - ${var.zones[each.value.zone_key].domain_name}",
  )
}

# http_request_late_transform. Request headers to the origin, applied after the
# security phases have run - so nothing set here can be matched by a WAF rule,
# and nothing set here can be used to evade one.
module "transform_rules" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//transform_rules"

  for_each = local.transform_policies
  zone_id  = data.cloudflare_zone.this[each.value.zone_key].id

  rules = each.value.transform_rules

  ruleset_name = coalesce(
    each.value.transform_ruleset_name,
    "Request headers - ${var.zones[each.value.zone_key].domain_name}",
  )
}

# http_request_origin. First matching rule wins here, the opposite of the cache
# phase.
module "origin_rules" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//origin_rules"

  for_each = local.origin_policies
  zone_id  = data.cloudflare_zone.this[each.value.zone_key].id

  rules = each.value.origin_rules

  ruleset_name = coalesce(
    each.value.origin_ruleset_name,
    "Origin rules - ${var.zones[each.value.zone_key].domain_name}",
  )
}

# http_request_dynamic_redirect. Single Redirects, for targets a Bulk Redirect
# cannot build. First match wins, and this phase runs before the WAF and before
# the account's Bulk Redirects, so a rule here shadows any Bulk row for the same
# URL.
module "redirect_rules" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//redirect_rules"

  for_each = local.redirect_policies
  zone_id  = data.cloudflare_zone.this[each.value.zone_key].id

  rules = each.value.redirect_rules

  ruleset_name = coalesce(
    each.value.redirect_ruleset_name,
    "Single redirects - ${var.zones[each.value.zone_key].domain_name}",
  )
}

# http_config_settings. Configuration Rules override zone settings, owned by
# layers/zones, for the requests they match - chiefly one hostname's SSL mode
# instead of lowering the whole zone's. Every matching rule applies and the
# last wins, as in the cache phase.
module "config_rules" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//config_rules"

  for_each = local.config_policies
  zone_id  = data.cloudflare_zone.this[each.value.zone_key].id

  rules = local.config_rules_for_module[each.key]

  ruleset_name = coalesce(
    each.value.config_ruleset_name,
    "Configuration rules - ${var.zones[each.value.zone_key].domain_name}",
  )
}
