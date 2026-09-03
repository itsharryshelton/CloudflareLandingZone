# Account-scoped Cloudflare Lists, one module instance per list.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//account_list?ref=v1.0.0"
module "account_list" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//account_list"

  for_each   = var.account_lists
  account_id = var.cloudflare_account_id

  name        = each.value.name
  kind        = each.value.kind
  description = each.value.description

  manage_items      = each.value.manage_items
  items             = each.value.items
  max_managed_items = each.value.max_managed_items
}
