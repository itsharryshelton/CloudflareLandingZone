# Adopting D1 databases that already exist.
#
# WHY THIS FILE EXISTS
# A D1 database name is unique within an account, so creating one that already
# exists is refused - after the plan was approved. Databases predate this layer
# for ordinary reasons: the workers layer owned them before D1 had a layer of
# its own, somebody ran `wrangler d1 create`, or this layer's state was lost.
# In each case the data is the thing worth keeping, and a second, empty
# database is the thing to avoid.
#
# So every declared name is looked up, and a match is imported instead of
# created. Once a database is in state its import is a no-op, including for the
# databases this layer created itself. No UUID is ever written down: the import
# ID, "<account_id>/<database_uuid>", is built from the lookup.
#
# READ THE FIRST PLAN AFTER AN ADOPTION. It reconciles the database against
# d1.tfvars:
#   - jurisdiction. Replace-on-change, so a mismatch fails preflight rather than
#     planning the destroy. Fix d1.tfvars to match what exists.
#   - primary_location_hint. Ignored after creation by the module, so a hint in
#     d1.tfvars never replaces an adopted database.
#   - read_replication_mode. Changes in place. A database switched to "auto" in
#     the dashboard is switched back if d1.tfvars says "disabled", and turning
#     replication off takes up to 24 hours to take effect. Left unset, the plan
#     shows the imported mode going to null: set it to the mode the database
#     already has to keep the adoption plan to the import alone.

# Each declared name, searched for. No databases declared, no API call.
data "cloudflare_d1_databases" "this" {
  for_each = var.d1_databases

  account_id = var.cloudflare_account_id
  name       = each.value.name
}

import {
  for_each = {
    for key, found in local.existing_d1_databases : key => (found.uuid != null ? found.uuid : found.id)
    if found != null
  }

  to = module.d1_databases[each.key].cloudflare_d1_database.this
  id = "${var.cloudflare_account_id}/${each.value}"
}
