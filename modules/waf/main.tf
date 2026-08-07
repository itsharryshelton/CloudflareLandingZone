# Rule mapping and normalisation lives in locals.tf.

# Zone-level entry-point ruleset for custom firewall logic.
resource "cloudflare_ruleset" "custom" {
  count = length(local.all_custom_rules) > 0 ? 1 : 0

  zone_id     = var.zone_id
  name        = var.custom_ruleset_name
  kind        = "zone"
  phase       = "http_request_firewall_custom"
  description = "Managed by Terraform (cloudflarelandingzone/modules/waf)."

  # Bot traffic rules, then baseline and tenant rules. This is the only ruleset
  # this zone may have in this phase, which is why bot traffic is an input here
  # rather than a resource in the zone_rules module.
  rules = local.all_custom_rules

  lifecycle {
    precondition {
      condition     = length(distinct(local.custom_rule_labels)) == length(local.custom_rule_labels)
      error_message = "Custom firewall rules must be uniquely labelled: two rules resolve to the same description, which makes them indistinguishable in the Cloudflare dashboard and in audit logs. Bot traffic rules are labelled \"Bot traffic - <behaviour> (<action>)\", so a hand-written rule can collide with one."
    }

    precondition {
      condition     = length(local.bot_traffic_empty_categories) == 0
      error_message = "bot_traffic.category_overrides sets an empty category list for: ${join(", ", local.bot_traffic_empty_categories)}. That would emit `cf.verified_bot_category in {}`, which Cloudflare rejects as a syntax error. Remove the behaviour from bot_traffic instead of overriding it with no categories."
    }
  }
}

# Zone-level entry-point ruleset for rate limiting.
resource "cloudflare_ruleset" "rate_limiting" {
  count = length(local.rate_limit_rules) > 0 ? 1 : 0

  zone_id     = var.zone_id
  name        = var.rate_limit_ruleset_name
  kind        = "zone"
  phase       = "http_ratelimit"
  description = "Managed by Terraform (cloudflarelandingzone/modules/waf)."

  rules = local.rate_limit_rules

  lifecycle {
    precondition {
      condition     = length(distinct(local.rate_limit_rule_labels)) == length(local.rate_limit_rule_labels)
      error_message = "rate_limiting_rules must have unique names: duplicates are indistinguishable in the Cloudflare dashboard and in audit logs."
    }
  }
}
