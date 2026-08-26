output "list_id" {
  value       = cloudflare_list.this.id
  description = "Opaque list identifier. This is what a Lists API load step needs: PUT /accounts/<account>/rules/lists/<list_id>/items."
}

output "name" {
  value       = cloudflare_list.this.name
  description = "List name, as a rule expression refers to it (`http.request.full_uri in $name`)."
}

output "num_items" {
  value       = cloudflare_list.this.num_items
  description = "How many rows Cloudflare holds in the list, counting rows loaded outside Terraform. Zero on a list whose data has not been loaded yet, which is the expected reading immediately after a first apply."
}

output "managed_item_count" {
  value       = local.managed_item_count
  description = "How many rows Terraform owns. Zero when manage_items is false, in which case the rows are the load step's business and an apply here will not touch them."
}

output "manage_items" {
  value       = var.manage_items
  description = "Whether Terraform owns this list's contents. True means an apply replaces every row, so a load step writing to the same list would be undone on the next run."
}

output "num_referencing_filters" {
  value       = cloudflare_list.this.num_referencing_filters
  description = "How many filters reference this list. A Bulk Redirect List is inert until an http_request_redirect rule names it, so this staying at zero is the usual reason a correctly-loaded list does nothing."
}
