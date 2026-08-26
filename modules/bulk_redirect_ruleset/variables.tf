variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. The Bulk Redirect ruleset is account-scoped: there is exactly one entry-point ruleset per account for the http_request_redirect phase, and this module owns it."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "name" {
  type        = string
  default     = "Bulk Redirects"
  description = "Human-readable name of the entry-point ruleset, as it appears in the dashboard. Cosmetic - Cloudflare identifies the ruleset by account and phase, not by this."
}

variable "description" {
  type        = string
  default     = "Managed by Terraform (cloudflarelandingzone/modules/bulk_redirect_ruleset)."
  description = "Free-text summary on the ruleset. The default says where the configuration lives, so somebody who finds a redirect they cannot explain in the dashboard knows not to edit it there."
}

variable "rules" {
  type = list(object({
    list_name   = string
    description = optional(string)
    enabled     = optional(bool, true)
    ref         = optional(string)

    scope_hostnames = optional(list(string), [])
    scope_domains   = optional(list(string), [])
  }))
  default     = []
  description = <<-EOT
    One rule per Bulk Redirect List, IN EVALUATION ORDER. Cloudflare stops at the
    first rule that redirects, so this is a list rather than a map: position is
    behaviour, and a map would be ordered lexically by key instead.

      - list_name      : the Bulk Redirect List this rule switches on. Must match
                         the list's name exactly - the expression refers to it as
                         `$list_name`.
      - description    : shown against the rule in the dashboard.
      - enabled        : false leaves the rule in place and inert, which is how a
                         list is taken out of service without deleting rows.
      - ref            : stable rule reference. Defaults to the list name, which
                         keeps a rule identifiable across reorders.
      - scope_hostnames: restrict the rule to these exact hostnames.
      - scope_domains  : restrict the rule to these zones - the apex and every
                         subdomain of each.

    SCOPING IS A BLAST-RADIUS CONTROL, NOT A ROUTING MECHANISM
    Every row already carries its own hostname, so an unscoped rule is correct and
    is the usual configuration. Scoping matters when one account holds several
    brands: it means a bad row loaded into one brand's list cannot redirect
    another brand's traffic, however wrong the source hostname on that row is.

    Both scope fields on one rule are combined with OR, and the result is ANDed
    with the list lookup.
  EOT

  validation {
    condition     = alltrue([for rule in var.rules : can(regex("^[a-z0-9_]{1,50}$", rule.list_name))])
    error_message = "Each rules[*].list_name must be 1-50 characters of lowercase letters, numbers and underscores - the same constraint Cloudflare puts on a list name, because this value is substituted into the rule expression as $list_name."
  }

  validation {
    condition     = length(distinct([for rule in var.rules : rule.list_name])) == length(var.rules)
    error_message = "Two rules reference the same list. Cloudflare stops at the first rule that redirects, so the second could only ever fire for traffic the first did not match - which for the same list is nothing."
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.rules : [
        for hostname in rule.scope_hostnames :
        can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", lower(hostname)))
      ]
    ]))
    error_message = "Each rules[*].scope_hostnames entry must be a fully-qualified, lowercase hostname (e.g. www.example.com) with no scheme, port or path."
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.rules : [
        for domain in rule.scope_domains :
        can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", lower(domain)))
      ]
    ]))
    error_message = "Each rules[*].scope_domains entry must be a bare domain name (e.g. example.com), with no scheme, wildcard or path. The module expands it to the apex and its subdomains."
  }

  validation {
    condition     = alltrue([for rule in var.rules : rule.ref == null || can(regex("^[a-zA-Z0-9_-]{1,64}$", coalesce(rule.ref, "x")))])
    error_message = "Each rules[*].ref, when set, must be 1-64 characters of letters, numbers, hyphens or underscores."
  }
}
