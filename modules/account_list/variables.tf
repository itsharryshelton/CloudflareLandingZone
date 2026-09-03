variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. Lists are account-scoped and referenced by name from a rule expression, so one list can serve every zone in the account."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "name" {
  type        = string
  description = <<-EOT
    List name. This is not a label: a rule refers to the list as `$name` inside
    its expression - `ip.src in $corporate_egress` - so renaming a list in use
    breaks every rule that reads it, and the break is a rule that quietly stops
    matching rather than an error.

    Cloudflare's constraint is lowercase letters, numbers and underscores only,
    to 50 characters. No hyphens, which is the usual first attempt.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9_]{1,50}$", var.name))
    error_message = "name must be 1-50 characters of lowercase letters, numbers and underscores only. Hyphens and capitals are rejected by Cloudflare, and the name is used as $name in a rule expression."
  }
}

variable "kind" {
  type        = string
  default     = "ip"
  description = <<-EOT
    What the list holds: ip, asn or hostname. A list's kind is fixed at creation,
    so changing it destroys and recreates the list - and any rule referring to it
    by name stops matching in the window between.

    "redirect" is deliberately not accepted here. Bulk Redirect Lists have their
    own row schema and their own ruleset phase; use ../bulk_redirect_list.
  EOT

  validation {
    condition     = contains(["ip", "asn", "hostname"], var.kind)
    error_message = "kind must be one of: ip, asn, hostname. For a redirect list use the bulk_redirect_list module instead."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Free-text summary shown in the dashboard. Worth spending: everywhere else a list is a name and a row count, and \"why is this address blocked\" is not a question the rows answer."
}

variable "manage_items" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether Terraform owns the contents of this list.

    False - the default - creates the list and leaves the rows alone. That is the
    right posture for an operationally maintained list: an address the security
    team adds during an incident must not be reverted by the next unrelated
    apply, and Cloudflare's `items` field is all-or-nothing ("If set, this
    overwrites all items in the list").

    True hands the rows to Terraform, so every row is in state, in every plan and
    in the pull request. Use it for a small, deliberate list - corporate egress
    ranges, a partner's payment gateway addresses - where a change ought to be
    reviewed before it takes effect.

    Switching true to false does not delete anything: Terraform stops managing
    the rows and leaves them in place.
  EOT
}

variable "items" {
  type = list(object({
    ip      = optional(string)
    asn     = optional(number)
    comment = optional(string)
    hostname = optional(object({
      url_hostname           = string
      exclude_exact_hostname = optional(bool)
    }))
  }))
  default     = []
  description = <<-EOT
    Rows, used only when `manage_items` is true. Exactly one of ip, asn or
    hostname per row, and it must be the one matching the list's `kind`.

      - `ip`       : an IPv4 address, IPv4 CIDR, IPv6 address or IPv6 CIDR.
      - `asn`      : a non-negative 32-bit autonomous system number.
      - `hostname` : url_hostname supports a leading wildcard.
      - `comment`  : why this row is here. Six months later this is the only
                     thing separating a deliberate entry from a forgotten one.
  EOT

  validation {
    condition = alltrue([
      for item in var.items :
      length([for v in [item.ip, item.asn, item.hostname] : v if v != null]) == 1
    ])
    error_message = "Each items entry must set exactly one of ip, asn or hostname."
  }

  validation {
    condition = alltrue([
      for item in var.items :
      item.asn == null || (item.asn >= 0 && item.asn <= 4294967295)
    ])
    error_message = "items[*].asn must be a non-negative 32-bit integer."
  }
}

variable "max_managed_items" {
  type        = number
  default     = 200
  description = "Ceiling on how many rows Terraform will own when manage_items is true. Cloudflare replaces the whole list on every apply, so every row sits in state and in every plan; past a few hundred that plan stops being reviewable and the list should be loaded through the Lists API instead."

  validation {
    condition     = var.max_managed_items > 0
    error_message = "max_managed_items must be greater than zero."
  }
}
