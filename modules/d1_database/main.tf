# One D1 database: Cloudflare's serverless SQLite, bound into a Worker as
# `env.<NAME>` and queried from it. Normalisation lives in locals.tf.
#
# The database is the only resource here. Its schema is not Terraform's to own -
# a migration is an ordered, versioned change to data that has to be applied once
# and in sequence, which is `wrangler d1 migrations apply` from the pipeline
# against the database_id this module outputs, not a plan that reconciles a
# desired state. Terraform owns the database and the binding; the application
# owns what is inside it.
#
# Every attribute Cloudflare accepts here is fixed at creation. Changing the
# name, the jurisdiction or the location replaces the database, and a replaced D1
# database is an empty one - there is no export taken first.

resource "cloudflare_d1_database" "this" {
  account_id = var.account_id
  name       = var.name

  primary_location_hint = var.primary_location_hint
  jurisdiction          = var.jurisdiction
  read_replication      = local.read_replication

  lifecycle {
    precondition {
      condition     = length(local.location_hint_outside_jurisdiction) == 0
      error_message = "The primary region asked for is outside the jurisdiction the database is restricted to: ${join(", ", local.location_hint_outside_jurisdiction)}. Cloudflare resolves this by refusing the create, after the apply has started. Drop the hint, or pick one inside the jurisdiction: eu takes weur or eeur, us and fedramp take wnam or enam."
    }
  }
}
