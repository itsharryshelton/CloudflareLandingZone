output "id" {
  description = "UUID of the DLP profile. This is what a Gateway HTTP policy matches on, and what the gateway module's match.dlp_profile_ids takes."
  value       = cloudflare_zero_trust_dlp_custom_profile.this.id
}

output "name" {
  description = "Display name of the profile."
  value       = cloudflare_zero_trust_dlp_custom_profile.this.name
}

output "entry_ids" {
  description = "Entry ID per entry name (lower-cased). What a Gateway log line or a support case names when it reports which pattern matched."
  value       = { for key, entry in cloudflare_zero_trust_dlp_custom_entry.this : key => entry.id }
}
