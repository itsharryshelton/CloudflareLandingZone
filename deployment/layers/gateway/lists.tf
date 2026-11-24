# Zero Trust lists, one module instance per list.
#
# In this layer rather than a layer of their own because Gateway policies are
# what read them: a policy names a list by key, the layer resolves the key to
# the list's UUID, and the list and the policy that reads it change in one plan
# under one approval. A separate layer would mean copying UUIDs between account
# trees by hand.
#
# Downstream deployments pin an immutable tag instead of the placeholder:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//zerotrust_list?ref=v1.0.0"
module "zerotrust_list" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//zerotrust_list"

  for_each   = var.gateway_lists
  account_id = var.cloudflare_account_id

  name        = each.value.name
  type        = each.value.type
  description = each.value.description
  items       = each.value.items
  max_items   = each.value.max_items
}
