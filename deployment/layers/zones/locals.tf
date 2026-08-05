# Joins the zone inventory to its configuration and applies platform defaults, so zones.tf reads as a plain module call.

locals {
  zones = {
    for key, zone in var.zones : key => {
      domain_name = zone.domain_name

      # A zone with no zone_config entry is legitimate - it gets the platform
      # baseline and no DNS records. lookup() rather than an index so that case
      # does not error.
      zone_type       = coalesce(try(var.zone_config[key].zone_type, null), "full")
      paused          = coalesce(try(var.zone_config[key].paused, null), false)
      ssl_mode        = coalesce(try(var.zone_config[key].ssl_mode, null), var.default_ssl_mode)
      min_tls_version = coalesce(try(var.zone_config[key].min_tls_version, null), var.default_min_tls_version)

      # Zone-specific settings win over the account-wide default.
      zone_settings = merge(
        var.default_zone_settings,
        try(var.zone_config[key].zone_settings, {}),
      )

      dns_records = try(var.zone_config[key].dns_records, [])
    }
  }

  # A zone_config entry whose key is not in the inventory is a typo that would
  # otherwise be silently ignored - the zone would deploy with no DNS records at all
  orphaned_zone_config_keys = [
    for key in keys(var.zone_config) : key
    if !contains(keys(var.zones), key)
  ]
}
