# Cloudflare One Client (WARP) configuration for one account: the account-wide
# device settings, the default device profile, custom profiles that override it
# for a matched set of devices, and each profile's Local Domain Fallback list.
#
# A profile decides what leaves a device through Cloudflare and what does not.
# Its split tunnel list is the boundary of everything Gateway can see: traffic
# excluded there never reaches a DNS, network or HTTP policy, and the dashboard
# gives no sign of it. That is why the split tunnel is modelled as one mode and
# one list, and why the checks below are as strict as they are.
#
# Input normalisation and the per-profile checks live in locals.tf.

# Singleton. Exists on every Zero Trust account, but provider 5.23 cannot import
# it, so the first apply writes it whole - hence every switch is a required
# input (see variables.tf).
resource "cloudflare_zero_trust_device_settings" "this" {
  count = var.device_settings == null ? 0 : 1

  account_id                            = var.account_id
  gateway_proxy_enabled                 = var.device_settings.gateway_proxy_enabled
  gateway_udp_proxy_enabled             = var.device_settings.gateway_udp_proxy_enabled
  root_certificate_installation_enabled = var.device_settings.root_certificate_installation_enabled
  use_zt_virtual_ip                     = var.device_settings.use_zt_virtual_ip
  disable_for_time                      = var.device_settings.disable_for_time

  external_emergency_signal_enabled     = try(var.device_settings.external_emergency_signal.enabled, null)
  external_emergency_signal_url         = try(var.device_settings.external_emergency_signal.url, null)
  external_emergency_signal_fingerprint = try(lower(var.device_settings.external_emergency_signal.fingerprint), null)
  external_emergency_signal_interval    = try(var.device_settings.external_emergency_signal.interval, null)
}

# Singleton. Cloudflare creates the default profile with the account, so the
# caller imports it; "creating" it would overwrite the fleet's live settings
# from this configuration alone.
resource "cloudflare_zero_trust_device_default_profile" "this" {
  count = var.default_profile == null ? 0 : 1

  account_id = var.account_id

  allow_mode_switch              = var.default_profile.allow_mode_switch
  allow_updates                  = var.default_profile.allow_updates
  allowed_to_leave               = var.default_profile.allowed_to_leave
  auto_connect                   = var.default_profile.auto_connect
  captive_portal                 = var.default_profile.captive_portal
  disable_auto_fallback          = var.default_profile.disable_auto_fallback
  exclude_office_ips             = var.default_profile.exclude_office_ips
  register_interface_ip_with_dns = var.default_profile.register_interface_ip_with_dns
  sccm_vpn_boundary_support      = var.default_profile.sccm_vpn_boundary_support
  support_url                    = var.default_profile.support_url
  switch_locked                  = var.default_profile.switch_locked
  tunnel_protocol                = var.default_profile.tunnel_protocol
  lan_allow_minutes              = var.default_profile.lan_allow_minutes
  lan_allow_subnet_size          = var.default_profile.lan_allow_subnet_size
  service_mode_v2                = var.default_profile.service_mode
  dns_search_suffixes            = var.default_profile.dns_search_suffixes
  virtual_networks               = var.default_profile.virtual_networks

  include = local.split_lists["default_profile"].mode == "include" ? local.split_lists["default_profile"].entries : null
  exclude = local.split_lists["default_profile"].mode == "exclude" ? local.split_lists["default_profile"].entries : null

  lifecycle {
    precondition {
      condition     = length(local.settings_problems["default_profile"]) == 0
      error_message = "default_profile is not valid: ${join("; ", local.settings_problems["default_profile"])}."
    }
  }
}

resource "cloudflare_zero_trust_device_custom_profile" "this" {
  for_each = local.custom_profiles

  account_id  = var.account_id
  name        = each.value.name
  description = each.value.description
  precedence  = each.value.precedence
  enabled     = each.value.enabled
  match       = local.matches[each.key]

  allow_mode_switch              = each.value.allow_mode_switch
  allow_updates                  = each.value.allow_updates
  allowed_to_leave               = each.value.allowed_to_leave
  auto_connect                   = each.value.auto_connect
  captive_portal                 = each.value.captive_portal
  disable_auto_fallback          = each.value.disable_auto_fallback
  exclude_office_ips             = each.value.exclude_office_ips
  register_interface_ip_with_dns = each.value.register_interface_ip_with_dns
  sccm_vpn_boundary_support      = each.value.sccm_vpn_boundary_support
  support_url                    = each.value.support_url
  switch_locked                  = each.value.switch_locked
  tunnel_protocol                = each.value.tunnel_protocol
  lan_allow_minutes              = each.value.lan_allow_minutes
  lan_allow_subnet_size          = each.value.lan_allow_subnet_size
  service_mode_v2                = each.value.service_mode
  dns_search_suffixes            = each.value.dns_search_suffixes
  virtual_networks               = each.value.virtual_networks

  include = local.split_lists["custom_profiles.${each.key}"].mode == "include" ? local.split_lists["custom_profiles.${each.key}"].entries : null
  exclude = local.split_lists["custom_profiles.${each.key}"].mode == "exclude" ? local.split_lists["custom_profiles.${each.key}"].entries : null

  lifecycle {
    precondition {
      condition     = length(local.settings_problems["custom_profiles.${each.key}"]) == 0 && length(local.match_problems[each.key]) == 0
      error_message = "custom_profiles.${each.key} is not valid: ${join("; ", concat(local.match_problems[each.key], local.settings_problems["custom_profiles.${each.key}"]))}."
    }

    precondition {
      condition     = length(local.duplicate_names) == 0
      error_message = "Two custom profiles share a name: ${join("; ", local.duplicate_names)}. Cloudflare allows it; this module does not, because the dashboard and the client both identify a profile by name."
    }

    # A tie leaves which profile a device gets to Cloudflare's tiebreak, which is
    # not documented and not visible in the dashboard.
    precondition {
      condition     = length(local.duplicate_precedences) == 0
      error_message = "Two custom profiles share a precedence: ${join("; ", local.duplicate_precedences)}. A device gets the first profile it matches, so a tie makes which settings it receives arbitrary. Give each profile its own precedence."
    }
  }
}

# Local Domain Fallback. A separate resource from the profile it belongs to,
# and a whole-list replacement: whatever is not declared here stops resolving
# locally once this applies.
resource "cloudflare_zero_trust_device_default_profile_local_domain_fallback" "this" {
  count = try(local.fallback_lists["default_profile"], null) == null ? 0 : 1

  account_id = var.account_id
  domains    = local.fallback_lists["default_profile"]

  # Validated with the profile it belongs to, so a bad suffix is reported once
  # and by profile name.
  depends_on = [cloudflare_zero_trust_device_default_profile.this]
}

resource "cloudflare_zero_trust_device_custom_profile_local_domain_fallback" "this" {
  for_each = {
    for key, profile in local.custom_profiles : key => local.fallback_lists["custom_profiles.${key}"]
    if profile.fallback_domains != null
  }

  account_id = var.account_id
  policy_id  = cloudflare_zero_trust_device_custom_profile.this[each.key].id
  domains    = each.value
}
