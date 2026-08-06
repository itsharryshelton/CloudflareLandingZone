# Account governance: who may sign in to this Cloudflare account, what they are
# allowed to do, and which permission bundles they inherit.

resource "cloudflare_account_member" "this" {
  for_each = local.members

  account_id = var.account_id
  email      = each.value.email
  roles      = each.value.roles
  status     = each.value.status
}

resource "cloudflare_user_group" "this" {
  for_each = local.user_groups

  account_id = var.account_id
  name       = each.value.name
  policies   = each.value.policies

  lifecycle {
    precondition {
      condition     = length(local.dangling_group_member_emails) == 0
      error_message = "user_groups names members that are not in var.members: ${join("; ", local.dangling_group_member_emails)}. Declared members: ${join(", ", local.member_keys)}. Add the member, or use member_ids for somebody who is deliberately managed outside this module."
    }
  }
}

# Split from the group itself because Cloudflare models membership as its own
# API object: a group can exist with nobody in it, and this resource owns the
# full list, so an address removed here loses the group's permissions.
resource "cloudflare_user_group_members" "this" {
  for_each = local.groups_with_members

  account_id    = var.account_id
  user_group_id = cloudflare_user_group.this[each.key].id
  members       = [for id in local.membership_ids[each.key] : { id = id }]
}
