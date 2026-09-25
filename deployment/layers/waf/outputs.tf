output "waf_policies" {
  description = "Per-policy ruleset IDs. A null means no rules of that kind were configured."
  value = {
    for key, policy in module.waf : key => {
      custom_ruleset_id        = policy.custom_ruleset_id
      rate_limiting_ruleset_id = policy.rate_limiting_ruleset_id
      managed_ruleset_id       = policy.managed_ruleset_id
    }
  }
}

output "managed_rulesets" {
  description = "Per-policy managed rulesets as deployed, rule description => Cloudflare ruleset ID. Empty for a policy with none. Check this to confirm a zone is executing the Cloudflare-authored rulesets you expect before relying on them."
  value       = { for key, policy in module.waf : key => policy.managed_rulesets_deployed }
}

output "managed_exceptions" {
  description = "Per-policy WAF exceptions as deployed, description => Cloudflare expression. Empty for a policy with none. Check this to see exactly which traffic is exempted from the managed rulesets."
  value       = { for key, policy in module.waf : key => policy.managed_exceptions }
}

output "bot_traffic_rules" {
  description = "Per-policy bot traffic rules as deployed, rule description => Cloudflare expression. Empty for a policy with no bot_traffic. Check this to confirm which verified bot categories each behaviour resolved to before trusting an allow."
  value       = { for key, policy in module.waf : key => policy.bot_traffic_rules }
}

output "resolved_zone_ids" {
  description = "Zone key => zone ID as resolved by name. Useful for confirming this layer bound to the zones you expected."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.id }
}
