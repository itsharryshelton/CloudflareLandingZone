# Resolves the names an operator writes into the IDs Cloudflare wants, applies
# the platform defaults, and derives every preflight assertion, so that
# account_governance.tf reads as a plain module call.

locals {
  # API catalogues, name -> ID
  role_ids_by_name = {
    for name, ids in {
      for role in try(data.cloudflare_account_roles.this.result, []) :
      lower(trimspace(role.name)) => role.id...
    } : name => ids[0]
  }

  # The reverse direction, so a restricted role is still caught when it is
  # granted by ID rather than by name.
  role_names_by_id = {
    for id, names in {
      for role in try(data.cloudflare_account_roles.this.result, []) :
      role.id => lower(trimspace(role.name))...
    } : id => names[0]
  }

  permission_group_ids_by_name = {
    for name, ids in {
      for group in try(data.cloudflare_account_permission_groups.this.result, []) :
      lower(trimspace(group.name)) => group.id...
    } : name => ids[0]
  }

  resource_group_ids_by_name = {
    for name, ids in {
      for group in try(data.cloudflare_resource_groups.this.result, []) :
      lower(trimspace(group.name)) => group.id...
    } : name => ids[0]
  }

  # A policy that names no resource group means "everything in this account".
  # Cloudflare expresses that as a resource group whose scope is the account
  # itself, which every account has, so it is found rather than invented.
  #
  # `scope` is a list in the provider schema even though an account has one, so
  # it is flattened to its keys rather than indexed.
  account_scope_key = "com.cloudflare.api.account.${var.cloudflare_account_id}"

  account_scope_resource_group_ids = [
    for group in try(data.cloudflare_resource_groups.this.result, []) : group.id
    if contains([for scope in try(group.scope, []) : scope.key], local.account_scope_key)
  ]

  # Members
  member_emails_by_key = {
    for key, member in var.account_members : key => lower(trimspace(member.email))
  }

  # A member naming no role gets the platform default rather than none at all
  member_role_names = {
    for key, member in var.account_members :
    key => length(member.role_names) > 0 ? member.role_names : var.default_role_names
  }

  # `if contains(...)` rather than a bare index: an unresolved name must reach
  # the operator as the preflight message naming it, not as "Invalid index"
  # pointing at this file.
  members_by_key = {
    for key, member in var.account_members : key => {
      email = local.member_emails_by_key[key]
      role_ids = distinct(concat(
        [
          for name in local.member_role_names[key] : local.role_ids_by_name[lower(trimspace(name))]
          if contains(keys(local.role_ids_by_name), lower(trimspace(name)))
        ],
        member.role_ids,
      ))
      status = member.status
    }
  }

  members = values(local.members_by_key)

  # User groups
  user_groups_by_key = {
    for key, group in var.user_groups : key => {
      name = group.name
      member_emails = [
        for member_key in group.member_keys : local.member_emails_by_key[member_key]
        if contains(keys(local.member_emails_by_key), member_key)
      ]
      member_ids = group.member_ids
      policies = [
        for policy in group.policies : {
          access = policy.access
          permission_group_ids = distinct(concat(
            [
              for name in policy.permission_group_names : local.permission_group_ids_by_name[lower(trimspace(name))]
              if contains(keys(local.permission_group_ids_by_name), lower(trimspace(name)))
            ],
            policy.permission_group_ids,
          ))
          resource_group_ids = distinct(concat(
            length(policy.resource_group_names) + length(policy.resource_group_ids) > 0
            ? [
              for name in policy.resource_group_names : local.resource_group_ids_by_name[lower(trimspace(name))]
              if contains(keys(local.resource_group_ids_by_name), lower(trimspace(name)))
            ]
            : local.account_scope_resource_group_ids,
            policy.resource_group_ids,
          ))
        }
      ]
    }
  }

  user_groups = values(local.user_groups_by_key)

  # Preflight check here
  unknown_role_names = distinct(flatten([
    for key, names in local.member_role_names : [
      for name in names : "account_members.${key} -> \"${name}\""
      if !contains(keys(local.role_ids_by_name), lower(trimspace(name)))
    ]
  ]))

  unknown_permission_group_names = distinct(flatten([
    for key, group in var.user_groups : [
      for index, policy in group.policies : [
        for name in policy.permission_group_names : "user_groups.${key}.policies[${index}] -> \"${name}\""
        if !contains(keys(local.permission_group_ids_by_name), lower(trimspace(name)))
      ]
    ]
  ]))

  unknown_resource_group_names = distinct(flatten([
    for key, group in var.user_groups : [
      for index, policy in group.policies : [
        for name in policy.resource_group_names : "user_groups.${key}.policies[${index}] -> \"${name}\""
        if !contains(keys(local.resource_group_ids_by_name), lower(trimspace(name)))
      ]
    ]
  ]))

  # A member_key pointing at nothing. Silently dropped, it would leave somebody
  # holding only the default minimal role and wondering why the dashboard is
  # empty.
  dangling_member_keys = distinct(flatten([
    for key, group in var.user_groups : [
      for member_key in group.member_keys : "user_groups.${key}.member_keys -> \"${member_key}\""
      if !contains(keys(var.account_members), member_key)
    ]
  ]))

  restricted_role_names = [for name in var.restricted_role_names : lower(trimspace(name))]

  # Effective role names per member: what was asked for by name, plus the names
  # behind anything asked for by ID. Checking only the names would leave the
  # restriction bypassable by pasting the ID of the same role.
  effective_role_names = {
    for key, member in var.account_members : key => distinct(concat(
      [for name in local.member_role_names[key] : lower(trimspace(name))],
      [for id in member.role_ids : lookup(local.role_names_by_id, id, id)],
    ))
  }

  restricted_roles_assigned = distinct(flatten([
    for key, names in local.effective_role_names : [
      for name in names : "account_members.${key} -> \"${name}\""
      if contains(local.restricted_role_names, name)
    ]
  ]))

  allowed_email_domains = [for domain in var.allowed_email_domains : lower(trimspace(domain))]

  members_from_disallowed_domains = length(local.allowed_email_domains) == 0 ? [] : [
    for key, email in local.member_emails_by_key : "account_members.${key} -> ${email}"
    if !contains(local.allowed_email_domains, try(split("@", email)[1], ""))
  ]

  # Which policies fall back to the account-wide resource group. Only then does
  # it matter whether exactly one was found, so the assertion is not made for an
  # account whose policies all name their scope explicitly.
  policies_defaulting_to_account_scope = distinct(flatten([
    for key, group in var.user_groups : [
      for index, policy in group.policies : "user_groups.${key}.policies[${index}]"
      if length(policy.resource_group_names) + length(policy.resource_group_ids) == 0
    ]
  ]))
}
