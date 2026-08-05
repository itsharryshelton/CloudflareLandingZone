# Rule mapping and normalisation lives in locals.tf.

# Zone-level entry-point ruleset for custom firewall logic.
resource "cloudflare_ruleset" "custom" {
  count = length(local.custom_rules) > 0 ? 1 : 0

  zone_id     = var.zone_id
  name        = var.custom_ruleset_name
  kind        = "zone"
  phase       = "http_request_firewall_custom"
  description = "Managed by Terraform (cloudflarelandingzone/modules/waf)."

  rules = local.custom_rules

  lifecycle {
    precondition {
      condition     = length(distinct(local.custom_rule_labels)) == length(local.custom_rule_labels)
      error_message = "custom_block_rules must be uniquely labelled: two rules resolve to the same description, which makes them indistinguishable in the Cloudflare dashboard and in audit logs."
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
