output "custom_profiles" {
  description = "Per-profile identity, keyed by the logical key: id, name, precedence, enabled and the match expression Cloudflare holds. The match is shown because it is the only way to see which devices a compiled profile actually selects."
  value = {
    for key, profile in cloudflare_zero_trust_device_custom_profile.this : key => {
      id         = profile.id
      name       = profile.name
      precedence = profile.precedence
      enabled    = profile.enabled
      match      = profile.match
    }
  }
}

output "custom_profile_ids" {
  description = "Logical key => custom device profile ID, for a DEX test or another layer to target."
  value       = { for key, profile in cloudflare_zero_trust_device_custom_profile.this : key => profile.id }
}

output "default_profile_id" {
  description = "ID of the default device profile, or null when this module does not manage it."
  value       = try(cloudflare_zero_trust_device_default_profile.this[0].id, null)
}

output "device_settings" {
  description = "The account-wide device settings as Cloudflare holds them, or null when unmanaged. Read gateway_proxy_enabled after the first apply: false means Gateway network and HTTP policies see no device traffic. The emergency signal URL and fingerprint are left out; they are not secret, but they name the endpoint that disconnects every client."
  value = try({
    gateway_proxy_enabled                 = cloudflare_zero_trust_device_settings.this[0].gateway_proxy_enabled
    gateway_udp_proxy_enabled             = cloudflare_zero_trust_device_settings.this[0].gateway_udp_proxy_enabled
    root_certificate_installation_enabled = cloudflare_zero_trust_device_settings.this[0].root_certificate_installation_enabled
    use_zt_virtual_ip                     = cloudflare_zero_trust_device_settings.this[0].use_zt_virtual_ip
    disable_for_time                      = cloudflare_zero_trust_device_settings.this[0].disable_for_time
    external_emergency_signal_enabled     = cloudflare_zero_trust_device_settings.this[0].external_emergency_signal_enabled
  }, null)
}
