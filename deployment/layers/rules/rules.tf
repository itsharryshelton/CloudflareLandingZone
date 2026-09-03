# Cache, transform and origin rulesets, per zone.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//cache_rules?ref=v1.0.0"

# http_request_cache_settings.
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

# http_request_late_transform.
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

# http_request_origin.
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
