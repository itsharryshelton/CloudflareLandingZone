output "custom_ruleset_id" {
  value       = length(cloudflare_ruleset.custom) > 0 ? cloudflare_ruleset.custom[0].id : null
  description = "ID of the custom firewall ruleset, or null when no custom_block_rules were supplied."
}

output "bot_traffic_rules" {
  value       = { for rule in local.bot_traffic_rules : rule.description => rule.expression }
  description = "The bot traffic rules this module generated, description => expression. Empty when bot_traffic is unset. Useful for confirming which verified bot categories a behaviour resolved to."
}

output "rate_limiting_ruleset_id" {
  value       = length(cloudflare_ruleset.rate_limiting) > 0 ? cloudflare_ruleset.rate_limiting[0].id : null
  description = "ID of the rate limiting ruleset, or null when no rate_limiting_rules were supplied."
}

output "managed_ruleset_id" {
  value       = length(cloudflare_ruleset.managed) > 0 ? cloudflare_ruleset.managed[0].id : null
  description = "ID of the managed rules ruleset, or null when no managed_rulesets were supplied."
}

output "managed_rulesets_deployed" {
  value       = { for rule in local.managed_ruleset_rules : rule.description => rule.action_parameters.id }
  description = "The managed rulesets this module executes, description => Cloudflare ruleset ID. The quickest check that a zone is running the rulesets you think it is."
}
