output "list_id" {
  value       = cloudflare_list.this.id
  description = "Opaque list identifier. This is what a Lists API load step needs: PUT /accounts/<account>/rules/lists/<list_id>/items."
}

output "name" {
  value       = cloudflare_list.this.name
  description = "List name, as a rule expression refers to it (`ip.src in $name`)."
}

output "kind" {
  value       = cloudflare_list.this.kind
  description = "What the list holds. Fixed at creation - changing it replaces the list."
}

output "num_items" {
  value       = cloudflare_list.this.num_items
  description = "How many rows Cloudflare holds, counting rows added outside Terraform. Zero on a list whose data has not been loaded yet, which is the expected reading immediately after a first apply."
}

output "managed_item_count" {
  value       = local.managed_item_count
  description = "How many rows Terraform owns. Zero when manage_items is false, in which case the rows belong to whoever loads them and an apply here will not touch them."
}

output "manage_items" {
  value       = var.manage_items
  description = "Whether Terraform owns this list's contents. True means an apply replaces every row, so an address added through the dashboard during an incident is removed on the next run."
}

output "num_referencing_filters" {
  value       = cloudflare_list.this.num_referencing_filters
  description = "How many filters reference this list. A list is inert until a rule names it, so this staying at zero is the usual reason a correctly-populated blocklist blocks nothing."
}
