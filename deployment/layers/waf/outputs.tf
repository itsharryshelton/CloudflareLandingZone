output "waf_policies" {
  description = "Per-policy ruleset IDs. A null means no rules of that kind were configured."
  value = {
    for key, policy in module.waf : key => {
      custom_ruleset_id        = policy.custom_ruleset_id
      rate_limiting_ruleset_id = policy.rate_limiting_ruleset_id
    }
  }
}

output "bot_traffic_rules" {
  description = "Per-policy bot traffic rules as deployed, rule description => Cloudflare expression. Empty for a policy with no bot_traffic. Check this to confirm which verified bot categories each behaviour resolved to before trusting an allow."
  value       = { for key, policy in module.waf : key => policy.bot_traffic_rules }
}

output "resolved_zone_ids" {
  description = "Zone key => zone ID as resolved by name. Useful for confirming this layer bound to the zones you expected."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.id }
}
