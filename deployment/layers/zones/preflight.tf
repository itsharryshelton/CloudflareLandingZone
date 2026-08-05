resource "terraform_data" "preflight" {
  input = { zones = length(var.zones) }

  lifecycle {
    precondition {
      condition     = length(local.orphaned_zone_config_keys) == 0
      error_message = "zone_config has entries with no matching zone in var.zones: ${join(", ", local.orphaned_zone_config_keys)}. Valid zone keys: ${join(", ", keys(var.zones))}. Left unchecked those zones would deploy with no DNS records."
    }
  }
}
