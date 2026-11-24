output "device_custom_profiles" {
  description = "Per-profile id, name, precedence, enabled flag and the match expression Cloudflare holds, keyed by the logical key. Read `match` after the first apply to confirm which devices a compiled profile selects."
  value       = module.device_profiles.custom_profiles
}

output "device_custom_profile_ids" {
  description = "Custom device profile ID per logical key, for a DEX test or another layer to target. No other layer can read this state, so copy it by hand."
  value       = module.device_profiles.custom_profile_ids
}

output "device_default_profile_id" {
  description = "ID of the default device profile, or null when this layer does not manage it."
  value       = module.device_profiles.default_profile_id
}

output "device_settings" {
  description = "The account-wide client settings as Cloudflare holds them, or null when unmanaged. gateway_proxy_enabled = false means no Gateway network or HTTP policy sees device traffic."
  value       = module.device_profiles.device_settings
}
