output "team_name" {
  description = "The Zero Trust team name, or null when this module does not manage the organisation. This is the subdomain of the team domain, and the value WARP clients enrol against."
  value       = local.team_name
}

output "auth_domain" {
  description = "The full team domain, for example acme.cloudflareaccess.com. Every Access login page and every service token lives under it."
  value       = one(cloudflare_zero_trust_organization.this[*].auth_domain)
}

output "identity_provider_ids" {
  description = "Identity provider ID per normalised provider name. This is the ID an Access rule or an application's allowed_idps needs."
  value       = { for key, provider in cloudflare_zero_trust_access_identity_provider.this : key => provider.id }
}

output "access_group_ids" {
  description = "Access group ID per normalised group name."
  value       = { for key, group in cloudflare_zero_trust_access_group.this : key => group.id }
}

output "access_policy_ids" {
  description = "Access policy ID per normalised policy name. Reusable policies, so this is what another application attaches to."
  value       = { for key, policy in cloudflare_zero_trust_access_policy.this : key => policy.id }
}

output "service_token_client_ids" {
  description = "Service token client ID per normalised token name, for the CF-Access-Client-Id header. Not a secret on its own, and useless without the matching client secret."
  value       = { for key, token in cloudflare_zero_trust_access_service_token.this : key => token.client_id }
}

output "service_token_expires_at" {
  description = "Expiry timestamp per normalised service token name. A token past this date fails silently from the caller's point of view, so it is the first thing to check when a machine integration stops working."
  value       = { for key, token in cloudflare_zero_trust_access_service_token.this : key => token.expires_at }
}

output "access_applications" {
  description = "Access application ID, AUD tag and primary domain, keyed by normalised application name. The AUD is what an origin validates the Cf-Access-Jwt-Assertion token against."
  value = {
    for key, application in cloudflare_zero_trust_access_application.this : key => {
      id     = application.id
      aud    = application.aud
      domain = application.domain
    }
  }
}
