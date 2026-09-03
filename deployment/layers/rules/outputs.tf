output "rule_policies" {
  description = "Per-policy ruleset IDs by phase. A null means no rules of that kind were configured, so no ruleset was created."
  value = {
    for key, policy in var.rule_policies : key => {
      cache_ruleset_id     = try(module.cache_rules[key].ruleset_id, null)
      transform_ruleset_id = try(module.transform_rules[key].ruleset_id, null)
      origin_ruleset_id    = try(module.origin_rules[key].ruleset_id, null)
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

output "resolved_zone_ids" {
  description = "Zone key => zone ID as resolved by name. Useful for confirming this layer bound to the zones you expected."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.id }
}
