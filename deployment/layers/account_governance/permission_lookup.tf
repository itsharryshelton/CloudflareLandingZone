# Role, permission group and resource group names -> IDs.
#
# `terraform validate` reports this data source as deprecated, and it is used
# knowingly. Cloudflare is moving from roles to permission groups, but the
# `roles` attribute on cloudflare_account_member is current and is what the
# dashboard's member list shows, and the singular cloudflare_account_role data
# source can only be queried by ID. Enumerating roles so that an account tree can
# say "DNS" rather than a hex string has no non-deprecated equivalent today.
#
# When it is removed, members move from roles to inline policies, which is the
# same permission-group-and-resource-group pair `user_groups` already builds.
data "cloudflare_account_roles" "this" {
  account_id = var.cloudflare_account_id
}

data "cloudflare_account_permission_groups" "this" {
  account_id = var.cloudflare_account_id
}

data "cloudflare_resource_groups" "this" {
  account_id = var.cloudflare_account_id
}
