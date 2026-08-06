output "team_domain" {
  description = "The account's Zero Trust team domain, for example acme.cloudflareaccess.com. Every Access login page and every WARP enrolment uses it."
  value       = module.zerotrust.auth_domain
}

output "team_name" {
  description = "The team name alone, without the cloudflareaccess.com suffix. This is what a WARP client is configured with."
  value       = module.zerotrust.team_name
}

output "identity_providers" {
  description = "Identity provider ID per normalised provider name. Needed when a rule elsewhere has to reference a provider by ID rather than by key."
  value       = module.zerotrust.identity_provider_ids
}

output "access_groups" {
  description = "Access group ID per normalised group name."
  value       = module.zerotrust.access_group_ids
}

output "access_policies" {
  description = "Access policy ID per normalised policy name. These are reusable policies, so this is what another application attaches to."
  value       = module.zerotrust.access_policy_ids
}

output "service_token_client_ids" {
  description = "Client ID per normalised service token name, for the CF-Access-Client-Id header. Not a secret on its own, and useless without the matching client secret."
  value       = module.zerotrust.service_token_client_ids
}

output "service_token_expires_at" {
  description = "Expiry timestamp per normalised service token name. An expired token fails the same way a wrong one does, so this is the first thing to check when a machine integration stops working."
  value       = module.zerotrust.service_token_expires_at
}

output "access_applications" {
  description = "Access application ID, AUD tag and primary domain, keyed by normalised application name. The AUD is what an origin validates the Cf-Access-Jwt-Assertion header against, which is how the origin stops accepting requests that did not come through Access."
  value       = module.zerotrust.access_applications
}
