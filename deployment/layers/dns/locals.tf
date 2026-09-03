locals {
  # Only zones that actually have records
  zones_with_records = {
    for key, config in var.dns_config : key => {
      domain_name = var.zones[key].domain_name
      dns_records = config.dns_records
    }
    if contains(keys(var.zones), key) && length(config.dns_records) > 0
  }

  orphaned_dns_config_keys = [
    for key in keys(var.dns_config) : key
    if !contains(keys(var.zones), key)
  ]
}
