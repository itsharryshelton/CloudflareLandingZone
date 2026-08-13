output "policy_ids" {
  description = "Gateway policy ID per normalised policy name. This is what a Cloudflare support case, an audit export or an out-of-band API call needs to identify a rule."
  value       = module.gateway.policy_ids
}

output "policies_by_type" {
  description = "Normalised policy names grouped by DNS, network and HTTP, each list in the order Gateway evaluates them. This is the enforced rule order and the first thing to check when a policy is not doing what it looks like it should - Gateway stops at the first allow or block that matches, so a rule can be perfectly correct and never reached."
  value       = module.gateway.policies_by_type
}

output "policy_precedence" {
  description = "Precedence and type per normalised policy name. Precedence is per type, so a DNS and an HTTP policy sharing a number are not in conflict."
  value       = module.gateway.policy_precedence
}

output "policy_expressions" {
  description = "The Cloudflare wirefilter expressions the selectors compiled into, per normalised policy name. Read this to confirm what a set of names turned into before trusting it, and to paste an expression into the Gateway dashboard's expression editor when reproducing a match."
  value       = module.gateway.policy_expressions
}

output "policies_logging_dlp_payloads" {
  description = "Normalised names of the policies with DLP payload logging turned on, which store the matched content itself in Gateway's logs. Empty is the expected state, and this output exists so that it can be checked rather than assumed."
  value       = module.gateway.policies_logging_dlp_payloads
}

output "resolved_category_count" {
  description = "How many Cloudflare content and security categories this account's catalogue offers. A sudden change between runs means Cloudflare has added or renamed categories, which is worth knowing before a category name stops resolving."
  value       = length(local.category_ids_by_name)
}

output "resolved_application_count" {
  description = "How many Gateway applications and app types this account's catalogue offers. Same reason as resolved_category_count: the catalogue is Cloudflare's, and it moves."
  value       = local.application_name_count
}
