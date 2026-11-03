# One D1 database per d1_databases entry.
#
# The database is the only thing Terraform owns. Its tables come from
# migrations/<key>/, applied by .github/scripts/d1-migrations.sh straight after
# this layer's apply, and its rows belong to the application.
#
# Bindings are not here. A Worker binds a database by key in the workers layer,
# which resolves the key to this database's UUID by name (workers/d1_lookup.tf)
# rather than reading this layer's state. This layer applies in tier 2 and
# workers in tier 3, so a new database and its migrations exist before any
# Worker is deployed against them.
#
# Downstream deployments pin an immutable tag instead of the local path - review root readme.md for more info:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/d1_database?ref=v1.0.0"
module "d1_databases" {
  source = "../../../modules/d1_database"

  for_each = local.d1_databases

  account_id = var.cloudflare_account_id
  name       = each.value.name

  primary_location_hint = each.value.primary_location_hint
  jurisdiction          = each.value.jurisdiction
  read_replication_mode = each.value.read_replication_mode
}
