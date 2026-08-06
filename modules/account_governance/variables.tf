variable "account_id" {
  type        = string
  description = "Cloudflare Account ID whose dashboard access this module governs."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "members" {
  type = list(object({
    email    = string
    role_ids = list(string)
    status   = optional(string)
  }))
  default     = []
  description = <<-EOT
    People who may sign in to this Cloudflare account's dashboard, and the roles
    they hold.

      - email    : the invitee's address. This is the member's identity here -
                   records are keyed on it, lower-cased and trimmed, so
                   reordering the list never moves a membership. Changing an
                   address destroys the membership and sends a fresh invite.
      - role_ids : one or more Cloudflare role IDs (32-char hex). At least one is
                   required: the Cloudflare API rejects a member carrying neither
                   a role nor a policy, and adding them to a user group later in
                   the same apply is too late. Grant the least privileged role
                   that works and layer extra permissions on with `user_groups`.
      - status   : (Optional) "accepted" or "pending". Leave unset, which is not
                   the same as "pending": the attribute is computed, so Terraform
                   accepts whatever Cloudflare reports and the invitation can
                   move from pending to accepted without showing as drift. Set it
                   only to force a state, and note that moving an already
                   accepted member back to "pending" replaces the membership -
                   the person loses access and is re-invited.

    Removing an entry revokes that person's access to the account on the next
    apply.
  EOT

  validation {
    condition = alltrue([
      for m in var.members :
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", lower(trimspace(m.email))))
    ])
    error_message = "Each members[*].email must be a single valid email address, with no spaces."
  }

  validation {
    condition = length(distinct([
      for m in var.members : lower(trimspace(m.email))
    ])) == length(var.members)
    error_message = "members contains duplicate email addresses. Addresses are compared lower-cased and trimmed, so \"Bob@example.com\" and \"bob@example.com\" collide - one membership per person."
  }

  validation {
    condition     = alltrue([for m in var.members : length(m.role_ids) > 0])
    error_message = "Each members[*] entry must list at least one role_id. Cloudflare rejects a member with no roles, so an account with no suitable role still needs the minimal-access one."
  }

  validation {
    condition = alltrue(flatten([
      for m in var.members : [
        for id in m.role_ids : can(regex("^[0-9a-f]{32}$", id))
      ]
    ]))
    error_message = "Each members[*].role_ids entry must be a 32-character hexadecimal Cloudflare role identifier."
  }

  validation {
    condition = alltrue([
      for m in var.members : m.status == null ? true : contains(["accepted", "pending"], m.status)
    ])
    error_message = "members[*].status must be \"accepted\" or \"pending\" when set."
  }
}

variable "user_groups" {
  type = list(object({
    name          = string
    member_emails = optional(list(string), [])
    member_ids    = optional(list(string), [])
    policies = list(object({
      access               = optional(string, "allow")
      permission_group_ids = list(string)
      resource_group_ids   = list(string)
    }))
  }))
  default     = []
  description = <<-EOT
    Account-owned user groups: a named bundle of permission policies, and the
    members who receive them. This is how a permission set is granted to several
    people at once instead of being re-entered per member.

      - name          : the group's display name in the dashboard, and its
                        identity here. Groups are keyed on it, lower-cased and
                        trimmed. Renaming a group destroys and recreates it.
      - member_emails : addresses drawn from `var.members`. They are resolved to
                        the membership IDs this module creates, so a member and
                        their group placement can be added in one apply.
      - member_ids    : (Optional) membership IDs of people who exist on the
                        account but are not managed here - an escape hatch for a
                        gradual adoption, not the normal path. An ID that is not
                        also in `var.members` will not be revoked by this module.
      - policies      : at least one. Each grants (`access = "allow"`) or refuses
                        (`"deny"`) a set of permission groups over a set of
                        resource groups. A group with no policy grants nothing.

    Deny wins over allow in Cloudflare's evaluation, which makes a deny policy a
    usable way to carve a capability back out of a broad allow.
  EOT

  validation {
    condition     = alltrue([for g in var.user_groups : trimspace(g.name) != ""])
    error_message = "Each user_groups[*].name must be a non-empty display name."
  }

  validation {
    condition = length(distinct([
      for g in var.user_groups : lower(trimspace(g.name))
    ])) == length(var.user_groups)
    error_message = "user_groups contains duplicate names. Names are compared lower-cased and trimmed, and they are the group's identity - each group must be uniquely named."
  }

  validation {
    condition     = alltrue([for g in var.user_groups : length(g.policies) > 0])
    error_message = "Each user_groups[*] entry must declare at least one policy. A group with no policies grants nothing and silently leaves its members without the access they were added for."
  }

  validation {
    condition = alltrue(flatten([
      for g in var.user_groups : [
        for p in g.policies : contains(["allow", "deny"], p.access)
      ]
    ]))
    error_message = "Each user_groups[*].policies[*].access must be \"allow\" or \"deny\"."
  }

  validation {
    condition = alltrue(flatten([
      for g in var.user_groups : [
        for p in g.policies : length(p.permission_group_ids) > 0 && length(p.resource_group_ids) > 0
      ]
    ]))
    error_message = "Each user_groups[*].policies[*] must name at least one permission group and at least one resource group. Cloudflare rejects a policy that scopes nothing to nothing."
  }

  validation {
    condition = alltrue(flatten([
      for g in var.user_groups : [
        for p in g.policies : [
          for id in concat(p.permission_group_ids, p.resource_group_ids) :
          can(regex("^[0-9a-f]{32}$", id))
        ]
      ]
    ]))
    error_message = "Each user_groups[*].policies[*] permission_group_ids and resource_group_ids entry must be a 32-character hexadecimal Cloudflare identifier."
  }

  validation {
    condition = alltrue(flatten([
      for g in var.user_groups : [
        for id in g.member_ids : can(regex("^[0-9a-f]{32}$", id))
      ]
    ]))
    error_message = "Each user_groups[*].member_ids entry must be a 32-character hexadecimal Cloudflare membership identifier."
  }

  validation {
    condition = alltrue(flatten([
      for g in var.user_groups : [
        for email in g.member_emails : trimspace(email) != ""
      ]
    ]))
    error_message = "user_groups[*].member_emails must not contain empty strings."
  }
}
