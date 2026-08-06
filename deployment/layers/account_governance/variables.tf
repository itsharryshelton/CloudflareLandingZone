# Layer account_governance - inputs.
#
# One config file feeds it:
#   accounts/<account>/account_governance.tfvars
#
# Operators name roles, permission groups and resource groups. The IDs behind
# those names are per-account and are resolved here through the Cloudflare API
# (permission_lookup.tf), so nothing in an account tree carries a 32-character
# hex string nobody can read.
variable "cloudflare_account_id" {
  type        = string
  description = <<-EOT
    Cloudflare Account ID this layer run targets. Supplied from
    accounts/<account>/account.tfvars, or overridden with
    TF_VAR_cloudflare_account_id.
  EOT

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "account_members" {
  description = <<-EOT
    People who may sign in to this Cloudflare account, keyed by a logical key.

    Unlike `zones`, the key here is a handle, not identity: user groups reference
    a member by it, and renaming one moves nothing in Cloudflare because
    memberships are keyed on the email address. Changing an `email` is the
    destructive edit - it revokes the old address and sends a fresh invitation.

    - `email`      - The person's address. Cloudflare emails them an invitation;
                     they cannot sign in until they accept it.
    - `role_names` - (Optional) Account role names as they appear in the
                     dashboard under Manage Account, then Members, for example
                     "Administrator Read Only" or "DNS". Matched
                     case-insensitively. Defaults to var.default_role_names.
    - `role_ids`   - (Optional) Role IDs, for a role whose name is ambiguous or
                     absent from the dashboard list. Merged with role_names.
    - `status`     - (Optional) Leave unset. The attribute is computed, so an
                     invitation moving from pending to accepted is not drift. Set
                     it only to force a state, and be aware that dragging an
                     accepted member back to "pending" replaces the membership:
                     they lose access and are re-invited.

    Deleting an entry revokes that person's access on the next apply.
  EOT
  type = map(object({
    email      = string
    role_names = optional(list(string), [])
    role_ids   = optional(list(string), [])
    status     = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.account_members) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "account_members keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = alltrue([
      for m in var.account_members :
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", lower(trimspace(m.email))))
    ])
    error_message = "Each account_members[*].email must be a single valid email address, with no spaces."
  }

  validation {
    condition = length(distinct([
      for m in var.account_members : lower(trimspace(m.email))
    ])) == length(var.account_members)
    error_message = "Two account_members entries share an email address. Addresses are compared lower-cased, and Cloudflare allows one membership per person per account - give the person one key with every role they need."
  }

  validation {
    condition = alltrue(flatten([
      for m in var.account_members : [
        for id in m.role_ids : can(regex("^[0-9a-f]{32}$", id))
      ]
    ]))
    error_message = "Each account_members[*].role_ids entry must be a 32-character hexadecimal Cloudflare role identifier. Use role_names for anything you can read off the dashboard."
  }
}

variable "user_groups" {
  description = <<-EOT
    Named permission bundles granted to several members at once, keyed by a
    logical key. Use one wherever the same permission set would otherwise be
    typed out per member.

    The key is a handle. The `name` is identity: renaming it destroys and
    recreates the group, and its members lose the group's permissions until the
    apply finishes.

    - `name`        - Display name in the dashboard.
    - `member_keys` - (Optional) Keys from var.account_members. The layer
                      resolves them to membership IDs, so a new member and their
                      group placement can land in one apply.
    - `member_ids`  - (Optional) Membership IDs of people deliberately managed
                      outside Terraform. Not revoked by this layer.
    - `policies`    - At least one. Each entry grants or denies a set of
                      permissions over a set of resources:
                        - `access`                 - (Optional) "allow" or "deny". Defaults to allow.
                        - `permission_group_names` - Permission group names, for example
                                                     "DNS Write". Matched case-insensitively.
                        - `permission_group_ids`   - (Optional) IDs, merged with the names above.
                        - `resource_group_names`   - (Optional) Resource group names. Left empty,
                                                     the policy covers the whole account.
                        - `resource_group_ids`     - (Optional) IDs, merged with the names above.

    Cloudflare evaluates deny before allow, which makes a deny policy a workable
    way to carve one capability back out of a broad grant.
  EOT
  type = map(object({
    name        = string
    member_keys = optional(list(string), [])
    member_ids  = optional(list(string), [])
    policies = list(object({
      access                 = optional(string, "allow")
      permission_group_names = optional(list(string), [])
      permission_group_ids   = optional(list(string), [])
      resource_group_names   = optional(list(string), [])
      resource_group_ids     = optional(list(string), [])
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.user_groups) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "user_groups keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for g in var.user_groups : lower(trimspace(g.name))
    ])) == length(var.user_groups)
    error_message = "Two user_groups entries share a name. The name is the group's identity in Cloudflare, so each group must be uniquely named."
  }

  validation {
    condition     = alltrue([for g in var.user_groups : length(g.policies) > 0])
    error_message = "Each user_groups entry must declare at least one policy. A group with no policies grants nothing, and its members would be added to it for no effect."
  }

  validation {
    condition = alltrue(flatten([
      for g in var.user_groups : [
        for p in g.policies : length(p.permission_group_names) + length(p.permission_group_ids) > 0
      ]
    ]))
    error_message = "Each user_groups[*].policies[*] must name at least one permission group, through permission_group_names or permission_group_ids."
  }
}

# Platform defaults (defaults.auto.tfvars)
variable "default_role_names" {
  type        = list(string)
  default     = ["Minimal Account Access"]
  description = <<-EOT
    Roles given to any member that names none of its own. The default is
    Cloudflare's least privileged account role: it is enough to satisfy the API,
    which rejects a member holding no role at all, and grants nothing beyond
    signing in. Everything the person actually needs then arrives through a user
    group, where it is named once and auditable in one place.
  EOT

  validation {
    condition     = length(var.default_role_names) > 0
    error_message = "default_role_names must name at least one role. Cloudflare rejects a member with no roles, so a member that names none would fail mid-apply instead."
  }
}

variable "restricted_role_names" {
  type        = list(string)
  default     = ["Super Administrator - All Privileges"]
  description = <<-EOT
    Roles this layer refuses to assign. The plan fails naming the member and the
    role, whether it was requested by name or by ID.

    Super Administrator is restricted by default because it is the one role that
    can rewrite the account's own access model, including removing the people who
    would notice. Granting it should be a deliberate edit to this list on a pull
    request that says why, not a one-word addition to an account tree.

    Emptying the list disables the check.
  EOT
}

variable "allowed_email_domains" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Email domains a member may be invited from, for example ["example.com"].
    Matched case-insensitively against the part after the "@". Empty, the
    default, allows any domain.

    Set it wherever the account should only ever be reachable by staff of one
    organisation: it turns a mistyped or unexpected external address into a
    failed plan rather than an invitation nobody notices.
  EOT

  validation {
    condition     = alltrue([for domain in var.allowed_email_domains : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", lower(trimspace(domain))))])
    error_message = "Each allowed_email_domains entry must be a bare domain such as example.com - no \"@\", no scheme, no path."
  }
}
