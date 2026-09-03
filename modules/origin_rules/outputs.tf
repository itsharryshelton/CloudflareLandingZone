output "ruleset_id" {
  value       = length(cloudflare_ruleset.this) > 0 ? cloudflare_ruleset.this[0].id : null
  description = "ID of the origin ruleset, or null when no rules were supplied."
}

output "rule_order" {
  value       = local.rule_labels
  description = "Rule descriptions in the order Cloudflare will evaluate them."
}
