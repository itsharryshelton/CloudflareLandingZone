# Applies the platform defaults, matches each declared database to one already
# at Cloudflare, and derives the preflight assertions, so that d1.tf reads as
# one plain module call.

locals {
  d1_databases = {
    for key, database in var.d1_databases : key => {
      name = database.name

      primary_location_hint = database.primary_location_hint != null ? database.primary_location_hint : var.default_d1_primary_location_hint
      read_replication_mode = database.read_replication_mode != null ? database.read_replication_mode : var.default_d1_read_replication_mode

      # No fleet default on purpose. A jurisdiction is a compliance decision about
      # one database's data, and one applied to every database by a file nobody
      # re-reads is how a database ends up restricted for no reason anybody can
      # name - or unrestricted for the same reason.
      jurisdiction = database.jurisdiction
    }
  }

  # Database key => the database already at Cloudflare under the declared name,
  # or null. The list endpoint's name filter is a search, not an exact match, so
  # the exact name is picked out here. Drives the import in imports.tf, and
  # includes the databases this layer created itself - importing those is a
  # no-op.
  existing_d1_databases = {
    for key, database in var.d1_databases : key => one([
      for found in data.cloudflare_d1_databases.this[key].result : found
      if found.name == database.name
    ])
  }

  # Preflight

  # Replication is resolved rather than read from var, so a database that
  # inherits "auto" from the fleet default is caught as well as one that asks for
  # it.
  replicated_d1_in_jurisdiction = var.allow_replicated_d1_in_jurisdiction ? [] : [
    for key, database in local.d1_databases : "d1_databases.${key} (\"${database.name}\", jurisdiction \"${database.jurisdiction}\")"
    if database.jurisdiction != null && database.read_replication_mode == "auto"
  ]

  # Jurisdiction is replace-on-change, so adopting a database under a different
  # one would destroy it in the same apply that adopted it. Empty and null both
  # mean unrestricted.
  adopted_jurisdiction_mismatches = [
    for key, found in local.existing_d1_databases :
    "d1_databases.${key} (\"${found.name}\") exists with jurisdiction \"${coalesce(found.jurisdiction, "none")}\", declared \"${coalesce(local.d1_databases[key].jurisdiction, "none")}\""
    if found != null && coalesce(found.jurisdiction, "none") != coalesce(local.d1_databases[key].jurisdiction, "none")
  ]
}
