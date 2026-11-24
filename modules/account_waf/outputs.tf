output "custom_ruleset_id" {
  value       = length(cloudflare_ruleset.custom) > 0 ? cloudflare_ruleset.custom[0].id : null
  description = "ID of the account custom ruleset, or null when no custom_rules were supplied."
}

output "custom_entrypoint_id" {
  value       = length(cloudflare_ruleset.custom_entrypoint) > 0 ? cloudflare_ruleset.custom_entrypoint[0].id : null
  description = "ID of the account's http_request_firewall_custom entry point, or null when no custom_rules were supplied."
}

output "managed_entrypoint_id" {
  value       = length(cloudflare_ruleset.managed_entrypoint) > 0 ? cloudflare_ruleset.managed_entrypoint[0].id : null
  description = "ID of the account's http_request_firewall_managed entry point, or null when no managed_rulesets were supplied."
}

output "deploy_expression" {
  value       = local.custom_deploy_expression
  description = "The zone scope every execute rule is deployed with. Confirms which zones the account-level rules reach."
}

output "managed_rulesets_deployed" {
  value       = { for rule in local.managed_ruleset_rules : rule.description => rule.action_parameters.id }
  description = "The managed rulesets executed at account level, description => Cloudflare ruleset ID."
}

output "managed_exceptions" {
  value       = { for rule in local.managed_exception_rules : rule.description => rule.expression }
  description = "The exceptions placed ahead of the account-level managed rulesets, description => expression."
}
