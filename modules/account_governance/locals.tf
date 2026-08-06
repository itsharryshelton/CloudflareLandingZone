# Keying for account membership and user groups.
#
# User groups are keyed on the name, renaming a group is a destroy and recreate, and its members go
# with it. Both keys are lower-cased and trimmed so that a change of casing is
# not read as a different person or a different group.

locals {
  # Members
  member_keys = [for m in var.members : lower(trimspace(m.email))]

  members = {
    for m in var.members : lower(trimspace(m.email)) => {
      email = lower(trimspace(m.email))

      # A set, not a list: Cloudflare returns roles in its own order, and a list
      # would show a diff every time that order differed from the tfvars.
      roles = toset(m.role_ids)

      status = m.status
    }
  }

  # User groups
  user_groups = {
    for g in var.user_groups : lower(trimspace(g.name)) => {
      name          = trimspace(g.name)
      member_emails = distinct([for email in g.member_emails : lower(trimspace(email))])
      member_ids    = distinct(g.member_ids)

      # The provider takes policies as a list of objects holding lists of
      # {id = ...} objects, which is a shape nobody wants to type into a tfvars
      # file. The operator supplies flat ID lists and the wrapping happens here.
      policies = [
        for p in g.policies : {
          access            = p.access
          permission_groups = [for id in distinct(p.permission_group_ids) : { id = id }]
          resource_groups   = [for id in distinct(p.resource_group_ids) : { id = id }]
        }
      ]
    }
  }

  dangling_group_member_emails = distinct(flatten([
    for g in var.user_groups : [
      for email in g.member_emails :
      "user group \"${trimspace(g.name)}\" -> ${lower(trimspace(email))}"
      if !contains(local.member_keys, lower(trimspace(email)))
    ]
  ]))

  groups_with_members = {
    for key, g in local.user_groups : key => g
    if length(g.member_emails) + length(g.member_ids) > 0
  }

  # Membership IDs per group
  membership_ids = {
    for key, g in local.groups_with_members : key => concat(
      [
        for email in g.member_emails : cloudflare_account_member.this[email].id
        if contains(local.member_keys, email)
      ],
      g.member_ids
    )
  }
}
