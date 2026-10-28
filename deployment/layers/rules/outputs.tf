output "rule_policies" {
  description = "Per-policy ruleset IDs by phase. A null means no rules of that kind were configured, so no ruleset was created."
  value = {
    for key, policy in var.rule_policies : key => {
      cache_ruleset_id     = try(module.cache_rules[key].ruleset_id, null)
      transform_ruleset_id = try(module.transform_rules[key].ruleset_id, null)
      origin_ruleset_id    = try(module.origin_rules[key].ruleset_id, null)
      redirect_ruleset_id  = try(module.redirect_rules[key].ruleset_id, null)
      config_ruleset_id    = try(module.config_rules[key].ruleset_id, null)
    }
  }
}

output "cache_rule_order" {
  description = "Cache rule descriptions per policy, in evaluation order. The LAST match wins in this phase, so read this to confirm the exceptions sit after the broad rules - a \"cache everything\" rule at the bottom re-enables caching on every path above it."
  value       = { for key, policy in module.cache_rules : key => policy.rule_order }
}

output "origin_rule_order" {
  description = "Origin rule descriptions per policy, in evaluation order. The FIRST match wins in this phase, the opposite of the cache phase."
  value       = { for key, policy in module.origin_rules : key => policy.rule_order }
}

output "redirect_rule_order" {
  description = "Single Redirect descriptions per policy, in evaluation order. The FIRST match redirects, so a broad rule above a specific one hides it."
  value       = { for key, policy in module.redirect_rules : key => policy.rule_order }
}

output "config_rule_order" {
  description = "Configuration rule descriptions per policy, in evaluation order. Every matching rule applies and the LAST one wins for a setting two rules both set, as in the cache phase."
  value       = { for key, policy in module.config_rules : key => policy.rule_order }
}

output "resolved_zone_ids" {
  description = "Zone key => zone ID as resolved by name. Useful for confirming this layer bound to the zones you expected."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.id }
}
