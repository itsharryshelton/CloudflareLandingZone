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

# Adopting existing account entry points. An account may already have one from
# the dashboard or an earlier tool; creating a second fails, so it is imported
# and its rules replaced by this layer's on the first apply. Read only when
# account-level WAF is on, so an unentitled account makes no extra API call.
data "cloudflare_rulesets" "account" {
  count = var.account_waf_enabled ? 1 : 0

  account_id = var.cloudflare_account_id
}

import {
  # Only when the module will declare the entry point, or the import has no target
  for_each = {
    for phase, ruleset_id in local.existing_account_entrypoints : phase => ruleset_id
    if phase == "http_request_firewall_custom" && ruleset_id != null && length(local.account_waf_custom_rules) > 0
  }

  to = module.account_waf[0].cloudflare_ruleset.custom_entrypoint[0]
  id = "accounts/${var.cloudflare_account_id}/${each.value}"
}

import {
  for_each = {
    for phase, ruleset_id in local.existing_account_entrypoints : phase => ruleset_id
    if phase == "http_request_firewall_managed" && ruleset_id != null && length(local.account_waf_managed_rulesets) > 0
  }

  to = module.account_waf[0].cloudflare_ruleset.managed_entrypoint[0]
  id = "accounts/${var.cloudflare_account_id}/${each.value}"
}
