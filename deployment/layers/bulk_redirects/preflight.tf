# Cross-variable checks. A module block cannot carry lifecycle.precondition and
# variable validation cannot compare two variables, so they live on a state-only
# resource from Terraform's built-in provider. No credentials, no API calls.
#
# This layer resolves nothing through the API, so every condition here is decided
# from variables alone and fires in CI's offline plan.

resource "terraform_data" "preflight" {
  input = {
    bulk_redirect_lists = length(var.bulk_redirect_lists)
    bulk_redirect_rules = length(var.bulk_redirect_rules)
    zones               = length(var.zones)
  }

  lifecycle {
    precondition {
      condition     = length(local.dangling_list_keys) == 0
      error_message = "A rule references a list this layer does not declare: ${join("; ", local.dangling_list_keys)}. Valid keys: ${join(", ", keys(var.bulk_redirect_lists))}."
    }

    precondition {
      condition     = length(local.dangling_scope_zone_keys) == 0
      error_message = "A rule scope references a zone key that is not in var.zones: ${join("; ", local.dangling_scope_zone_keys)}. Valid keys: ${join(", ", keys(var.zones))}. Both layers must be given the same accounts/<account>/zones.tfvars."
    }

    precondition {
      condition     = length(local.unreferenced_lists) == 0
      error_message = "These lists have no rule referencing them: ${join("; ", local.unreferenced_lists)}. A list with no rule holds its rows, counts against the account's list quota and redirects nothing. Add a bulk_redirect_rules entry - with enabled = false if it is deliberately staged or rolled back, so the hold is visible - or set allow_unreferenced_lists = true in layers/bulk_redirects/defaults.auto.tfvars."
    }

    precondition {
      condition     = length(local.hostnames_outside_inventory) == 0
      error_message = "These hostnames sit in no zone in var.zones: ${join(", ", local.hostnames_outside_inventory)}. Cloudflare accepts a redirect on a hostname the account does not serve and it simply never matches, so the list looks loaded, the rule looks enabled, and nothing redirects. Add the zone to zones.tfvars, fix the hostname, or set allow_hostnames_outside_zone_inventory = true where the zone is deliberately managed elsewhere."
    }

    precondition {
      condition     = length(local.items_without_manage_items) == 0
      error_message = "These lists supply rows but do not set manage_items: ${join("; ", local.items_without_manage_items)}. The rows would be silently ignored while the list appeared configured. Set manage_items = true to have Terraform own them - remembering it then replaces the whole list on every apply - or remove them and load the list through the Lists API."
    }

    precondition {
      condition     = length(local.oversized_lists) == 0
      error_message = "These lists declare more rows than Terraform should own: ${join("; ", local.oversized_lists)}. Cloudflare replaces the entire list on every write, so each row is in state and in every plan. Set manage_items = false and load the rows with a PUT to /accounts/<account>/rules/lists/<list_id>/items against the list_id this layer outputs, or raise max_managed_items on the list."
    }

    precondition {
      condition     = length(var.bulk_redirect_lists) <= var.max_bulk_redirect_lists
      error_message = "This account declares ${length(var.bulk_redirect_lists)} Bulk Redirect Lists, over the max_bulk_redirect_lists ceiling of ${var.max_bulk_redirect_lists}. Cloudflare enforces the quota list by list at apply time, so an over-quota plan applies cleanly up to the limit and then fails - leaving some lists created and the ruleset referencing one that is not. Ask the account team to raise the real quota before raising this."
    }

    precondition {
      condition     = length(var.bulk_redirect_rules) <= var.max_bulk_redirect_rules
      error_message = "This account declares ${length(var.bulk_redirect_rules)} Bulk Redirect rules, over the max_bulk_redirect_rules ceiling of ${var.max_bulk_redirect_rules}. As with lists, Cloudflare enforces this at apply time rather than at plan time."
    }
  }
}
