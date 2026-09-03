# Operator-facing rules -> the shape cloudflare_ruleset wants.

locals {
  rules = [
    for rule in var.rules : {
      action      = "set_cache_settings"
      expression  = rule.expression
      description = coalesce(rule.description, rule.name)
      enabled     = rule.enabled

      action_parameters = {
        cache                      = rule.cache
        cache_key                  = rule.cache_key
        edge_ttl                   = rule.edge_ttl
        browser_ttl                = rule.browser_ttl
        serve_stale                = rule.serve_stale
        respect_strong_etags       = rule.respect_strong_etags
        origin_cache_control       = rule.origin_cache_control
        origin_error_page_passthru = rule.origin_error_page_passthru
        read_timeout               = rule.read_timeout
      }
    }
  ]

  rule_labels = [for rule in local.rules : rule.description]

  empty_rules = [
    for rule in var.rules : rule.name
    if rule.cache == null
    && rule.cache_key == null
    && rule.edge_ttl == null
    && rule.browser_ttl == null
    && rule.serve_stale == null
    && rule.respect_strong_etags == null
    && rule.origin_cache_control == null
    && rule.origin_error_page_passthru == null
    && rule.read_timeout == null
  ]
}
