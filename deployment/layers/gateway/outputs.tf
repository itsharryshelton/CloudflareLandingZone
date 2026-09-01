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

output "inspection_certificate_id" {
  description = "ID of the inspection CA managed by this layer, or null where the account's certificate is not managed here. This is what the Gateway configuration's certificate field is set to."
  value       = module.gateway.inspection_certificate_id
}

output "inspection_certificate_binding_status" {
  description = "Deployment state of the inspection CA at Cloudflare's edge. Activation is asynchronous, so a run can end at pending_deployment; available is the state in which Gateway can decrypt with it, and it is worth reading before enabling tls_decrypt in the next change."
  value       = module.gateway.inspection_certificate_binding_status
}

output "inspection_certificate_pem" {
  description = "The inspection CA in PEM form - the public root every device on WARP has to trust before inspection is turned on. Hand it to whatever distributes certificates to the estate. No private key is involved: this is what Gateway presents to every client."
  value       = module.gateway.inspection_certificate_pem
}

output "inspection_certificate_expires_on" {
  description = "When the inspection CA expires. Expiry with inspection on is every HTTPS request failing across the estate, and the replacement root has to reach devices before that date rather than after it."
  value       = module.gateway.inspection_certificate_expires_on
}
