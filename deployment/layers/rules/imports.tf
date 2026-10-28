# Adopting a zone's existing Single Redirects or Configuration Rules entry point.
#
# A zone may hold exactly one entry-point ruleset per phase, and one created in
# the dashboard or by an earlier tool stays until it is deleted. Creating over
# it is rejected outright:
#
#   20217: 'zone' is not a valid value for kind because exceeded maximum number
#          of zone rulesets for phase http_request_dynamic_redirect
#
# So it is imported instead, and the same apply replaces its rules with the
# policy's. REVIEW THAT PLAN: a rule it shows being removed is a live redirect
# or setting override made outside Terraform, and the apply deletes it. Either
# carry it into the policy's redirect_rules or config_rules, or confirm it is
# unwanted. Read the current entry point with:
#   curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
#     "https://api.cloudflare.com/client/v4/zones/<zone_id>/rulesets/phases/<phase>/entrypoint" \
#     | jq '.result.rules[] | {description, enabled, expression, action_parameters}'
#
# Config rules are covered because an urgent per-hostname override, such as an
# SSL mode for an origin returning 526, is often made by hand in the dashboard
# first - and that entry point would otherwise block the Terraform one.

# Every ruleset on each zone with redirect or config rules
data "cloudflare_rulesets" "this" {
  for_each = local.zones_with_adopted_phases

  zone_id = data.cloudflare_zone.this[each.key].id
}

import {
  # Only zones that already have an entry point. Once it is in state this is a
  # no-op, including for the entry points this layer created itself.
  for_each = {
    for key, ruleset_id in local.existing_redirect_entrypoints : key => ruleset_id
    if ruleset_id != null
  }

  to = module.redirect_rules[each.key].cloudflare_ruleset.this[0]
  id = "zones/${data.cloudflare_zone.this[var.rule_policies[each.key].zone_key].id}/${each.value}"
}

import {
  for_each = {
    for key, ruleset_id in local.existing_config_entrypoints : key => ruleset_id
    if ruleset_id != null
  }

  to = module.config_rules[each.key].cloudflare_ruleset.this[0]
  id = "zones/${data.cloudflare_zone.this[var.rule_policies[each.key].zone_key].id}/${each.value}"
}
