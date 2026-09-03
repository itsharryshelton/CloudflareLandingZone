output "lists" {
  description = "Per-list identity and contents posture. `name` is what a rule expression must say after the $; `manage_items` false means the row count is whatever the operators have loaded, not what this repository declares."
  value = {
    for key, list in module.account_list : key => {
      list_id            = list.list_id
      name               = list.name
      kind               = list.kind
      num_items          = list.num_items
      managed_item_count = list.managed_item_count
      manage_items       = list.manage_items
    }
  }
}

output "list_ids_for_api_load" {
  description = "List name => list ID, for a pipeline step that loads rows through the Lists API: PUT /accounts/<account>/rules/lists/<list_id>/items. Only lists Terraform does not own the contents of are included, because loading into a Terraform-owned list is undone on the next apply."
  value = {
    for key, list in module.account_list : list.name => list.list_id
    if !list.manage_items
  }
}

output "unreferenced_lists" {
  description = "Lists that no rule refers to yet. A list is inert until something names it, so an entry here is the usual explanation for a correctly-populated blocklist that blocks nothing. Expected to be non-empty immediately after a first apply, when the layer that references it has not run."
  value = [
    for key, list in module.account_list : list.name
    if list.num_referencing_filters == 0
  ]
}
