output "ruleset_id" {
  value       = try(cloudflare_ruleset.this[0].id, null)
  description = "ID of the account's http_request_redirect entry-point ruleset, or null when no rules are declared and no ruleset is created."
}

output "rule_count" {
  value       = length(local.rules)
  description = "How many rules the ruleset carries - one per Bulk Redirect List switched on. Cloudflare caps rules per account by plan, so this is the number to compare against that quota."
}

output "expressions" {
  value       = local.expressions
  description = "List name => the rules-language expression generated for it. Worth reading on a first apply: this is exactly what Cloudflare evaluates, and a scope that is wider or narrower than intended shows here rather than in traffic."
}

output "disabled_rules" {
  value       = local.disabled_rules
  description = "Lists whose rule is present but switched off. Their rows are still loaded and still cost list quota, and they redirect nothing - so a name lingering here is either a deliberate hold or a migration nobody finished."
}
