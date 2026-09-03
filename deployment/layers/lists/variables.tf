# Layer lists - inputs.
#
# Account-scoped Cloudflare Lists: the named containers that rule expressions
# refer to as `$name`. IP blocklists, corporate egress ranges, partner address
# ranges. Holds its own state, so an apply here can never propose destroying a
# zone or a ruleset.
#
# This layer touches no zone, so it applies in the same tier as `zones` - which
# is what makes it safe for the `waf` layer, a tier later, to reference a list by
# name. Creating a list here and referencing it there in the same pull request
# works; the reverse order does not.
#
# Bulk Redirect Lists are NOT here. They have their own row schema and their own
# ruleset phase, and live in the bulk_redirects layer.
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/lists.tfvars   - the lists, consumed only here

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Lists are account-scoped: one list is visible to every zone in the account, which is the point - a blocklist should not have to be maintained per zone."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "account_lists" {
  description = <<-EOT
    Account-scoped lists, keyed by a logical key. The key is Terraform's handle;
    `name` is what Cloudflare and every rule expression see.

    - `name`              - The list name, as `$name` in a rule expression. Lowercase
                            letters, numbers and underscores only, to 50 characters.
                            Renaming one breaks every rule that reads it, and breaks it
                            by silently matching nothing rather than by erroring.
    - `kind`              - ip | asn | hostname. Fixed at creation: changing it destroys
                            and recreates the list, and every rule referring to it
                            matches nothing until the new one exists.
    - `description`       - (Optional) Free text, shown in the dashboard.
    - `manage_items`      - (Optional, default false) Whether Terraform owns the rows.
    - `items`             - (Optional) The rows, used only when manage_items is true.
    - `max_managed_items` - (Optional, default 200) Ceiling on Terraform-owned rows.

    WHO OWNS THE CONTENTS
    This is the decision that matters, and the default is deliberate.

    manage_items = false leaves the rows alone entirely. Terraform creates the
    container and never reads or writes a row again. That is what an
    operationally maintained blocklist needs: an address added through the
    dashboard or the API during an incident takes effect immediately, needs no
    pull request, and is still there after the next unrelated apply of this
    layer.

    manage_items = true makes every apply authoritative over the contents -
    Cloudflare's items field overwrites the whole list - so anything added out of
    band is deleted on the next run. Use it for a small, stable, reviewable list:
    corporate egress ranges, a payment provider's published address ranges.
    Choosing it for an incident-response blocklist is how a block gets quietly
    reverted a week later by an unrelated change.
  EOT

  type = map(object({
    name              = string
    kind              = optional(string, "ip")
    description       = optional(string)
    manage_items      = optional(bool, false)
    max_managed_items = optional(number, 200)
    items = optional(list(object({
      ip      = optional(string)
      asn     = optional(number)
      comment = optional(string)
      hostname = optional(object({
        url_hostname           = string
        exclude_exact_hostname = optional(bool)
      }))
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.account_lists) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "account_lists keys must be lowercase alphanumeric with underscores."
  }

  validation {
    condition     = length(distinct([for l in var.account_lists : lower(l.name)])) == length(var.account_lists)
    error_message = "Two account_lists entries share a `name`. Cloudflare requires list names to be unique within an account, and the second create fails after the first has already been made."
  }
}
