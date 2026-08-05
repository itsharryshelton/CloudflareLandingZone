# Cross-variable checks. A module block cannot carry lifecycle.precondition and
# variable validation cannot compare two variables, so they live on a state-only
# resource from Terraform's built-in provider. No credentials, no API calls.

resource "terraform_data" "preflight" {
  input = {
    load_balancers   = length(var.load_balancers)
    referenced_zones = length(local.referenced_zones)
  }

  lifecycle {
    precondition {
      condition     = length(local.dangling_zone_keys) == 0
      error_message = "zone_key does not match any entry in var.zones: ${join("; ", local.dangling_zone_keys)}. Valid keys: ${join(", ", keys(var.zones))}. Both layers must be given the same accounts/<account>/zones.tfvars."
    }

    precondition {
      condition     = length(local.hostnames_outside_zone) == 0
      error_message = "A load balancer hostname is not inside the zone it references: ${join("; ", local.hostnames_outside_zone)}. Cloudflare would reject it only after creating the monitor and pool, leaving the layer half-applied."
    }
  }
}
