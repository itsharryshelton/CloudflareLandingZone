# One Bulk Redirect List. Normalisation lives in locals.tf.
#
# THE LIST AND ITS CONTENTS ARE SEPARABLE, ON PURPOSE
# Cloudflare models a list as a named container plus rows, and the provider's
# `items` field is all-or-nothing: "If set, this overwrites all items in the
# list." So there are exactly two coherent postures, and `manage_items` picks
# between them rather than leaving it to whether somebody happened to pass rows.
#
#   manage_items = false  Terraform owns the container. Rows are loaded through
#                         the Lists API - PUT .../rules/lists/<id>/items replaces
#                         the whole list in one asynchronous operation. This is
#                         what a real redirect table wants: the rows stay out of
#                         state and out of every plan.
#
#   manage_items = true   Terraform owns the rows too, and any row written by
#                         anything else is removed on the next apply.
#
# Nothing here creates the rule that switches the list on. A list is inert until
# an http_request_redirect rule references it, which is the bulk_redirect_ruleset
# module - one ruleset per account, not one per list.

resource "cloudflare_list" "this" {
  account_id  = var.account_id
  kind        = "redirect"
  name        = var.name
  description = var.description

  # null, not [], when unmanaged: an empty set is a valid instruction to delete
  # every row, and that is not what "Terraform does not own the contents" means.
  items = local.items

  lifecycle {
    precondition {
      condition     = var.manage_items || length(var.items) == 0
      error_message = "items were supplied but manage_items is false, so they would be silently ignored while the list appeared to be configured. Set manage_items = true to have Terraform own the rows, or remove them and load the list through the Lists API."
    }

    precondition {
      condition     = local.managed_item_count <= var.max_managed_items
      error_message = "This list declares ${local.managed_item_count} rows, over the max_managed_items ceiling of ${var.max_managed_items}. Cloudflare replaces the whole list on every apply, so every row is in state and in every plan. Set manage_items = false and load the rows with a PUT to /accounts/<account>/rules/lists/<list_id>/items, or raise the ceiling on a pull request that says why."
    }

    precondition {
      condition     = length(local.duplicate_sources) == 0
      error_message = "Two rows share a source URL: ${join(", ", local.duplicate_sources)}. Cloudflare rejects a list containing duplicate sources, and it does so after the list exists - so the list is created empty and the apply fails. Sources are compared lower-cased and trimmed here, because Cloudflare matches them that way."
    }
  }
}
