resource "terraform_data" "preflight" {
  input = {
    account_members = length(var.account_members)
    user_groups     = length(var.user_groups)
  }

  lifecycle {
    precondition {
      condition     = length(local.unknown_role_names) == 0
      error_message = "Unknown account role name: ${join("; ", local.unknown_role_names)}. Names are matched case-insensitively against the roles this account actually has: ${join(", ", sort(keys(local.role_ids_by_name)))}."
    }

    precondition {
      condition     = length(local.unknown_permission_group_names) == 0
      error_message = "Unknown permission group name: ${join("; ", local.unknown_permission_group_names)}. Cloudflare's catalogue is long and account-specific; check the exact wording in the dashboard under Manage Account, then Members, then Permission Groups, or supply permission_group_ids instead."
    }

    precondition {
      condition     = length(local.unknown_resource_group_names) == 0
      error_message = "Unknown resource group name: ${join("; ", local.unknown_resource_group_names)}. Available: ${join(", ", sort(keys(local.resource_group_ids_by_name)))}. Leave resource_group_names empty for a policy that should cover the whole account."
    }

    precondition {
      condition     = length(local.dangling_member_keys) == 0
      error_message = "member_keys does not match any entry in var.account_members: ${join("; ", local.dangling_member_keys)}. Valid keys: ${join(", ", sort(keys(var.account_members)))}. Left unchecked, that person would be created with only the default minimal role and none of the group's permissions."
    }

    precondition {
      condition     = length(local.restricted_roles_assigned) == 0
      error_message = "A restricted role was requested: ${join("; ", local.restricted_roles_assigned)}. Restricted roles are ${join(", ", var.restricted_role_names)}, set in layers/account_governance/defaults.auto.tfvars. Granting one is a deliberate change to that list, reviewed on its own pull request - not an account tree edit."
    }

    precondition {
      condition     = length(local.members_from_disallowed_domains) == 0
      error_message = "Member email outside the permitted domains: ${join("; ", local.members_from_disallowed_domains)}. Permitted: ${join(", ", local.allowed_email_domains)}, set through allowed_email_domains."
    }

    # Only asserted when something actually relies on the fallback. An account
    # whose policies all name their resource groups does not care how many
    # account-scoped groups exist.
    precondition {
      condition     = length(local.policies_defaulting_to_account_scope) == 0 || length(local.account_scope_resource_group_ids) == 1
      error_message = "These policies name no resource group and so should cover the whole account: ${join(", ", local.policies_defaulting_to_account_scope)}. Resolving that needs exactly one account-scoped resource group, and ${length(local.account_scope_resource_group_ids)} were found for ${var.cloudflare_account_id}. Name the scope explicitly with resource_group_names; available: ${join(", ", sort(keys(local.resource_group_ids_by_name)))}."
    }
  }
}
