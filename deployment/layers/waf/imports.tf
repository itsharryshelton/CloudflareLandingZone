# Adopting the zone's existing Managed Rules entry point.
#
# Cloudflare deploys the Cloudflare Managed Ruleset to every zone on a paid plan
# the moment the zone is created, meaning trying to deploy may fail for an API  because there is already an entry point.

# Every ruleset on each zone this layer touches
data "cloudflare_rulesets" "this" {
  for_each = local.zones_with_managed_rulesets

  zone_id = data.cloudflare_zone.this[each.key].id
}

import {
  # Only zones that already have an entry point.
  for_each = {
    for key, ruleset_id in local.existing_managed_entrypoints : key => ruleset_id
    if ruleset_id != null
  }

  to = module.waf[each.key].cloudflare_ruleset.managed[0]
  id = "zones/${data.cloudflare_zone.this[var.waf_policies[each.key].zone_key].id}/${each.value}"
}
