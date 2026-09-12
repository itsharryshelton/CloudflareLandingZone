# Turns the operator-facing schema into the shape the D1 API wants, and derives
# the values main.tf's preconditions assert on.
#
# The only mapping is `read_replication`, which the API nests one level deeper
# than an operator should have to write.

locals {
  # Left null when nothing was asked for, rather than sent as a disabled block:
  # an account with replication enabled elsewhere should not have it silently
  # turned off by a module that was never told about it.
  read_replication = var.read_replication_mode == null ? null : { mode = var.read_replication_mode }

  # Which primary regions each jurisdiction can actually hold. Cloudflare rejects
  # the combination itself, but only after the plan has been approved, and the
  # message names neither field.
  jurisdiction_regions = {
    eu      = ["weur", "eeur"]
    us      = ["wnam", "enam"]
    fedramp = ["wnam", "enam"]
  }

  location_hint_outside_jurisdiction = (
    var.jurisdiction == null || var.primary_location_hint == null
    ? []
    : contains(lookup(local.jurisdiction_regions, var.jurisdiction, []), var.primary_location_hint)
    ? []
    : ["primary_location_hint = \"${var.primary_location_hint}\" against jurisdiction = \"${var.jurisdiction}\""]
  )
}
