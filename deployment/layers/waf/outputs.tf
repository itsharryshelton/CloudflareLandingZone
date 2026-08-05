output "waf_policies" {
  description = "Per-policy ruleset IDs. A null means no rules of that kind were configured."
  value = {
    for key, policy in module.waf : key => {
      custom_ruleset_id        = policy.custom_ruleset_id
      rate_limiting_ruleset_id = policy.rate_limiting_ruleset_id
    }
  }
}

output "resolved_zone_ids" {
  description = "Zone key => zone ID as resolved by name. Useful for confirming this layer bound to the zones you expected."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.id }
}
