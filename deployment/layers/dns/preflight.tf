# Cross-variable checks

resource "terraform_data" "preflight" {
  input = {
    zones              = length(var.zones)
    zones_with_records = length(local.zones_with_records)
    records            = sum(concat([0], [for z in local.zones_with_records : length(z.dns_records)]))
  }

  lifecycle {
    precondition {
      condition     = length(local.orphaned_dns_config_keys) == 0
      error_message = "dns_config has entries with no matching zone in var.zones: ${join(", ", local.orphaned_dns_config_keys)}. Valid zone keys: ${join(", ", keys(var.zones))}. Left unchecked those records would apply to no zone at all and the plan would still go green."
    }
  }
}
