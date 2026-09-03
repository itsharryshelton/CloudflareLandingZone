# Zone-level entry-point ruleset for cache behaviour.
#
# Cloudflare permits one entry-point ruleset per phase per zone
resource "cloudflare_ruleset" "this" {
  count = length(local.rules) > 0 ? 1 : 0

  zone_id     = var.zone_id
  name        = var.ruleset_name
  kind        = "zone"
  phase       = "http_request_cache_settings"
  description = "Managed by Terraform (cloudflarelandingzone/modules/cache_rules)."

  rules = local.rules

  lifecycle {
    precondition {
      condition     = length(distinct(local.rule_labels)) == length(local.rule_labels)
      error_message = "Cache rules must be uniquely labelled: two rules resolve to the same description, which makes them indistinguishable in the Cloudflare dashboard and in audit logs."
    }

    precondition {
      condition     = length(local.empty_rules) == 0
      error_message = "These cache rules set no cache settings at all, so they match traffic and do nothing: ${join(", ", local.empty_rules)}. Set at least one of cache, cache_key, edge_ttl, browser_ttl, serve_stale, respect_strong_etags, origin_cache_control, origin_error_page_passthru or read_timeout."
    }
  }
}
