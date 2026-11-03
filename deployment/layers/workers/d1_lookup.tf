# D1 key -> database UUID, without reading the d1 layer's state.
#
# Only databases named by a binding's d1_database_key are read. A deployment
# whose Workers bind no D1 database looks nothing up. The match on the exact
# name, and the preflight message for a database that is not there yet, are in
# locals.tf.

data "cloudflare_d1_databases" "this" {
  for_each = local.referenced_d1_databases

  account_id = var.cloudflare_account_id
  name       = each.value.name
}
