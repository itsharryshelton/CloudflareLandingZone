# Layer bulk_redirects - inputs.
#
# Cloudflare Bulk Redirects: the account's redirect lists and the single
# entry-point ruleset that switches them on. Holds its own state, so an apply
# here can never propose destroying a zone.
#
# Config files:
#   accounts/<account>/account.tfvars         - the account ID, shared with every layer
#   accounts/<account>/zones.tfvars           - the zone inventory, shared with every layer
#   accounts/<account>/bulk_redirects.tfvars  - the lists and rules, consumed only here
#
# WHERE THE REDIRECT DATA LIVES
# Not here, and not in an account tree. A list's rows are data: a real table runs
# to tens or hundreds of thousands of them, Cloudflare replaces the whole list on
# every write, and Terraform would hold each row in state and re-plan all of them
# on every run. This layer creates the list and the rule; the pipeline loads the
# rows with a PUT to /accounts/<account>/rules/lists/<list_id>/items, against the
# list_id this layer outputs.
#
# Inline `items` exist for the small case - a dozen vanity URLs - and are gated
# behind `manage_items` so that "Terraform owns these rows" is always a decision
# somebody made rather than a side effect of pasting data in.
#
# This layer resolves nothing through the Cloudflare API, so it plans offline
# against every account on every push. Every guardrail below can be made to fire
# in CI without credentials.

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Bulk Redirect Lists and the redirect ruleset are both account-scoped."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: logical key => domain name. The same file the zones layer is
    given, so the keys mean the same thing in both.

    This layer creates no zone and looks none up - Bulk Redirects need no zone ID.
    The inventory is used to check that a hostname this layer redirects is one the
    account actually serves. A row whose source hostname sits in no zone here is
    accepted by Cloudflare and never matches a request, which is a failure mode
    with no symptom other than the redirect not happening.

    - `domain_name` - The apex domain (e.g. example.com).
    - `zone_tier`   - (Optional) The zone's Cloudflare rate plan. Unused by this
                      layer, and declared only so that the shared inventory file
                      can carry it for the zones and waf layers, which do gate on
                      it. Terraform rejects a .tfvars attribute that the variable
                      type does not declare, so omitting it here would break
                      every layer's run rather than just this one's.
  EOT
  type = map(object({
    domain_name = string
    zone_tier   = optional(string)
  }))

  validation {
    condition     = alltrue([for key in keys(var.zones) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "zones keys must be lowercase alphanumeric with underscores."
  }
}

variable "bulk_redirect_lists" {
  description = <<-EOT
    Bulk Redirect Lists, keyed by a logical key. A rule refers to a list by that
    key, so an account tree never carries a list ID.

    - `name`              - The list's name in Cloudflare. Lowercase letters,
                            numbers and underscores only, to 50 characters - the
                            rule expression refers to it as `$name`, which is why
                            hyphens are rejected. Renaming a list in use breaks
                            the rule that reads it.
    - `description`       - Free text shown in the dashboard.
    - `manage_items`      - (Optional) Whether Terraform owns the rows. Defaults
                            to `var.default_manage_items`, which is false: the
                            list is created empty and the pipeline loads it.
    - `items`             - (Optional) The rows, when `manage_items` is true.
                            See below.
    - `max_managed_items` - (Optional) Per-list override of
                            `var.default_max_managed_items`.

    ROWS
    Each item is a source and a target:

      - `source_url`           - hostname and path, e.g. "www.example.com/old".
                                 No scheme (so it matches http and https alike)
                                 and no query string (Cloudflare matches up to
                                 the "?" only).
      - `target_url`           - a FULL URL, e.g. "https://www.example.com/new".
                                 Bulk Redirects do not resolve a relative target
                                 against the request; a Worker doing this job
                                 does, which is the thing that catches people out
                                 when migrating one to the other.
      - `status_code`          - 301, 302, 307 or 308. Falls back to
                                 `var.default_status_code`.
      - `preserve_query_string` - carry the incoming query to the target. Falls
                                 back to `var.default_preserve_query_string`.
      - `include_subdomains`   - match subdomains of the source hostname too.
      - `subpath_matching`     - match paths below the source path too.
      - `preserve_path_suffix` - with subpath matching, carry the unmatched tail
                                 onto the target.
      - `comment`              - per-row note, stored with the item.
  EOT
  type = map(object({
    name         = string
    description  = optional(string)
    manage_items = optional(bool)

    items = optional(list(object({
      source_url = string
      target_url = string

      status_code           = optional(number)
      preserve_query_string = optional(bool)
      include_subdomains    = optional(bool)
      subpath_matching      = optional(bool)
      preserve_path_suffix  = optional(bool)

      comment = optional(string)
    })), [])

    max_managed_items = optional(number)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.bulk_redirect_lists) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "bulk_redirect_lists keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition     = length(distinct([for list in var.bulk_redirect_lists : lower(list.name)])) == length(var.bulk_redirect_lists)
    error_message = "Two bulk_redirect_lists entries share a name. A list name is unique within an account, and it is what a rule expression resolves - the second would adopt or fight over the first's list."
  }
}

variable "bulk_redirect_rules" {
  description = <<-EOT
    The rules that switch lists on, IN EVALUATION ORDER. Cloudflare stops at the
    first rule that redirects, so this is an ordered list rather than a map:
    position is behaviour.

    - `list_key`        - a key from `var.bulk_redirect_lists`.
    - `description`     - shown against the rule in the dashboard.
    - `enabled`         - (Optional) false leaves the rule in place and inert.
                          That is how a list is taken out of service without
                          deleting its rows, and how a migration is rolled back in
                          one apply.
    - `scope_zone_keys` - (Optional) keys from `var.zones`. Restricts the rule to
                          those zones - each apex and its subdomains.
    - `scope_hostnames` - (Optional) exact hostnames to restrict the rule to.

    SCOPING
    Every row carries its own hostname, so an unscoped rule is correct and is the
    normal configuration. Scope matters when one account holds several brands: it
    means a wrong row loaded into one brand's list cannot redirect another brand's
    traffic. On a single-brand account it buys nothing.

    A list with no rule here is inert - it holds rows, costs list quota and
    redirects nothing. `var.allow_unreferenced_lists` decides whether that fails
    the plan.
  EOT
  type = list(object({
    list_key    = string
    description = optional(string)
    enabled     = optional(bool, true)

    scope_zone_keys = optional(list(string), [])
    scope_hostnames = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = alltrue([for rule in var.bulk_redirect_rules : can(regex("^[a-z0-9_]+$", rule.list_key))])
    error_message = "Each bulk_redirect_rules[*].list_key must be lowercase alphanumeric with underscores, matching a key in bulk_redirect_lists."
  }

  validation {
    condition     = length(distinct([for rule in var.bulk_redirect_rules : rule.list_key])) == length(var.bulk_redirect_rules)
    error_message = "Two bulk_redirect_rules entries reference the same list. Cloudflare stops at the first rule that redirects, so the second could only fire for traffic the first did not match - which, for the same list, is nothing."
  }
}

# Platform defaults (defaults.auto.tfvars in this directory)
variable "default_manage_items" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a list that says nothing about it has its rows owned by Terraform.

    False is the right fleet default. A Bulk Redirect List is a data store:
    Cloudflare replaces the whole list on every write, so managed rows are in
    state, in every plan and in every apply. Terraform owns the container and the
    rule; the pipeline loads the rows.

    A list opts in with `manage_items = true` when its rows genuinely belong in a
    pull request - a handful of vanity URLs, a campaign redirect somebody needs to
    see reviewed.
  EOT
}

variable "default_status_code" {
  type        = number
  default     = 301
  description = <<-EOT
    Status code given to any row that names none.

    301 matches Cloudflare's own default and is what a permanent site migration
    wants. It is also close to irreversible in practice: browsers cache a 301
    aggressively and will not re-request the old URL for a long time, so a wrong
    301 outlives the fix. Use 302 while a migration is still being proven.
  EOT

  validation {
    condition     = contains([301, 302, 307, 308], var.default_status_code)
    error_message = "default_status_code must be 301, 302, 307 or 308. Bulk Redirects do not support 303."
  }
}

variable "default_preserve_query_string" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether a row that says nothing about it carries the incoming query string to
    its target.

    Cloudflare's own default is false. True is the better fleet default: a visitor
    arriving with `?utm_source=...` on an old URL loses the attribution entirely
    if the query is dropped, and the campaign it came from is what usually
    surfaces the broken link in the first place. A row whose target needs its own
    fixed query string turns it off.
  EOT
}

variable "default_max_managed_items" {
  type        = number
  default     = 500
  description = <<-EOT
    Ceiling on how many rows Terraform will own in one list, unless that list
    overrides it. Only applies where `manage_items` is true.

    The limit is about Terraform, not about Cloudflare - a Bulk Redirect List
    happily holds hundreds of thousands. See the `bulk_redirect_lists` description
    for where a real dataset goes instead.
  EOT

  validation {
    condition     = var.default_max_managed_items >= 0
    error_message = "default_max_managed_items must be zero or greater."
  }
}

variable "ruleset_name" {
  type        = string
  default     = "Bulk Redirects"
  description = "Name of the account's http_request_redirect entry-point ruleset, as it appears in the dashboard. Cosmetic - Cloudflare identifies the ruleset by account and phase."
}

# Guardrails
variable "max_bulk_redirect_lists" {
  type        = number
  default     = 25
  description = <<-EOT
    How many Bulk Redirect Lists this account may declare.

    25 is the Enterprise default quota. The check exists because Cloudflare
    enforces it at apply time, list by list: an over-quota plan applies cleanly up
    to the limit and then fails, leaving some lists created, some not, and the
    ruleset referencing a list that does not exist.

    Contact the account team to raise the real quota before raising this.
  EOT

  validation {
    condition     = var.max_bulk_redirect_lists >= 0
    error_message = "max_bulk_redirect_lists must be zero or greater."
  }
}

variable "max_bulk_redirect_rules" {
  type        = number
  default     = 50
  description = <<-EOT
    How many Bulk Redirect rules this account may declare.

    50 is the Enterprise default quota. As with lists, Cloudflare enforces it at
    apply time rather than at plan time, so the failure lands halfway through.
  EOT

  validation {
    condition     = var.max_bulk_redirect_rules >= 0
    error_message = "max_bulk_redirect_rules must be zero or greater."
  }
}

variable "allow_hostnames_outside_zone_inventory" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a source hostname or a rule scope may name a host that sits in no zone
    in `var.zones`.

    Cloudflare accepts such a row without complaint. It simply never matches,
    because the request never reaches this account - so the symptom is "the
    redirect does not work" with a list that looks correctly loaded and a rule that
    looks correctly enabled. It is the most common way a bulk redirect migration
    quietly does nothing.

    Left false, the plan fails naming the hostname. Turn it on where a zone is
    deliberately managed outside this Terraform and the inventory is incomplete.
  EOT
}

variable "allow_unreferenced_lists" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a list may exist with no rule referencing it.

    An unreferenced list is inert: it holds every row, counts against the account's
    list quota, and redirects nothing. That is occasionally deliberate - a list
    staged ahead of a cutover, or one held back after a rollback - and is
    otherwise a rule somebody forgot to add.

    Left false, the plan fails naming the list. A rule with `enabled = false` is
    the better way to stage or roll back, because it is visible in the dashboard
    and in this layer's `disabled_rules` output.
  EOT
}
