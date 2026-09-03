locals {
  ignored_items = [
    for key, list in var.account_lists : "${key} (${length(list.items)} rows)"
    if !list.manage_items && length(list.items) > 0
  ]
}
