# One account-scoped Cloudflare List (ip, asn or hostname).

resource "cloudflare_list" "this" {
  account_id  = var.account_id
  kind        = var.kind
  name        = var.name
  description = var.description

  items = local.items

  lifecycle {
    precondition {
      condition     = var.manage_items || length(var.items) == 0
      error_message = "items were supplied but manage_items is false, so they would be silently ignored while the list appeared to be configured. Set manage_items = true to have Terraform own the rows, or remove them and load the list through the Lists API."
    }

    precondition {
      condition     = length(local.mismatched_items) == 0
      error_message = "kind is \"${var.kind}\" but these rows do not set `${local.expected_field[var.kind]}`: ${join(", ", local.mismatched_items)}. Cloudflare rejects the row only after the list has been created, so the list exists and is empty when the apply fails."
    }

    precondition {
      condition     = local.managed_item_count <= var.max_managed_items
      error_message = "This list declares ${local.managed_item_count} rows, over the max_managed_items ceiling of ${var.max_managed_items}. Cloudflare replaces the whole list on every apply, so every row is in state and in every plan. Set manage_items = false and load the rows through the Lists API, or raise the ceiling on a pull request that says why."
    }

    precondition {
      condition     = length(local.duplicate_rows) == 0
      error_message = "Two rows are the same entry: ${join(", ", local.duplicate_rows)}. Cloudflare rejects a list containing duplicates, and does so after the list exists - so the list is created empty and the apply fails."
    }
  }
}
