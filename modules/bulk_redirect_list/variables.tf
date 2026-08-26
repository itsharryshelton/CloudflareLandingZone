variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. Bulk Redirect Lists are account-scoped and are referenced by name from a rule, so one list can serve hostnames in any zone in the account."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "name" {
  type        = string
  description = <<-EOT
    List name. This is not a label: a rule refers to the list as `$name` inside
    its expression, so renaming a list in use breaks the rule that reads it.

    Cloudflare's constraint is lowercase letters, numbers and underscores only,
    to 50 characters - no hyphens, which is the usual first attempt.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9_]{1,50}$", var.name))
    error_message = "name must be 1-50 characters of lowercase letters, numbers and underscores only. Hyphens and capitals are rejected by Cloudflare, and the name is used as $name in a rule expression."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Free-text summary shown in the dashboard. Worth spending: a list is a name and a row count everywhere else, and \"which brand is redirect_list_3\" is not a question the row data answers quickly."
}

variable "manage_items" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether Terraform owns the contents of this list.

    False - the default - creates the list and leaves the rows alone, so they can
    be loaded by the pipeline through the Lists API. That is the right shape for
    anything of size: a bulk redirect table is data, and Terraform would hold
    every row in state and re-plan all of them on every run.

    True hands the rows to Terraform, and Cloudflare's `items` field then
    overwrites the whole list on every apply. A row loaded by any other means is
    deleted the next time this applies. Use it only for a list small enough that
    the rows belong in a pull request.

    Switching from true to false does not delete anything: Terraform stops
    managing the rows and leaves them in place.
  EOT
}

variable "items" {
  type = list(object({
    source_url = string
    target_url = string

    status_code           = optional(number)
    preserve_query_string = optional(bool)
    include_subdomains    = optional(bool)
    subpath_matching      = optional(bool)
    preserve_path_suffix  = optional(bool)

    comment = optional(string)
  }))
  default     = []
  description = <<-EOT
    The redirects, when `manage_items` is true.

      - source_url           : hostname and path, e.g. "www.example.com/old". The
                               scheme is optional and is best omitted - without
                               one the redirect matches both http and https. A
                               query string is NOT allowed here; Cloudflare
                               matches on the URL up to the "?" only.
      - target_url           : where to send the request. A full URL including
                               the scheme, e.g. "https://www.example.com/new".
                               Bulk Redirects do not resolve a relative target
                               against the request, which is the main difference
                               from a Worker doing the same job.
      - status_code          : 301, 302, 307 or 308. Cloudflare defaults to 301.
                               301 and 308 are cached by browsers more or less
                               permanently - a wrong one is very hard to take
                               back.
      - preserve_query_string: carry the incoming query string to the target. Any
                               query string already on the target is discarded
                               when this is on.
      - include_subdomains   : also match subdomains of the source hostname, so
                               "example.com/a" matches "shop.example.com/a".
      - subpath_matching     : also match paths below the source path, so
                               "example.com/dir" matches "example.com/dir/page".
      - preserve_path_suffix : with subpath matching on, carry the unmatched tail
                               of the path onto the target. Meaningless without
                               `subpath_matching`.
      - comment              : per-row note, stored with the item.

    A source_url is matched exactly unless `include_subdomains` or
    `subpath_matching` widens it. That exactness is the point: a bulk list is a
    lookup table, not a pattern language. Anything needing a substitution or a
    regular expression is a Single Redirect instead.
  EOT

  validation {
    condition     = alltrue([for item in var.items : !can(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://", item.source_url))])
    error_message = "A source_url includes a scheme. Omit it - a scheme-less source matches both http and https, and writing \"https://\" narrows the redirect to HTTPS traffic without saying so."
  }

  validation {
    # regex rather than strcontains: this module keeps a >= 1.5.0 floor so it stays
    # usable from an older root module, and strcontains arrived in Terraform 1.7.
    condition     = alltrue([for item in var.items : !can(regex("\\?", item.source_url))])
    error_message = "A source_url contains a query string. Cloudflare matches Bulk Redirect sources on the URL up to the \"?\" only, so such a row can never fire. Use preserve_query_string to carry the query through, or a Single Redirect if the query is what you need to match on."
  }

  validation {
    condition     = alltrue([for item in var.items : !startswith(item.source_url, "/")])
    error_message = "A source_url is a bare path. Bulk Redirect sources are account-scoped and must carry the hostname, e.g. \"www.example.com/old-page\" rather than \"/old-page\"."
  }

  validation {
    condition     = alltrue([for item in var.items : can(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://", item.target_url))])
    error_message = "A target_url has no scheme. Bulk Redirects do not resolve a relative target against the incoming request - unlike a Worker - so the target must be a full URL such as \"https://www.example.com/new-page\"."
  }

  validation {
    condition     = alltrue([for item in var.items : length(trimspace(item.target_url)) == length(item.target_url)])
    error_message = "A target_url has leading or trailing whitespace. Cloudflare rejects it, and it is the usual symptom of a spreadsheet export."
  }

  validation {
    condition = alltrue([
      for item in var.items :
      item.status_code == null || contains([301, 302, 307, 308], coalesce(item.status_code, 301))
    ])
    error_message = "Each items[*].status_code must be null, 301, 302, 307 or 308. Bulk Redirects do not support 303."
  }

  validation {
    condition = alltrue([
      for item in var.items :
      !coalesce(item.preserve_path_suffix, false) || coalesce(item.subpath_matching, false)
    ])
    error_message = "An item sets preserve_path_suffix without subpath_matching. The suffix only exists when a subpath matched, so on its own the flag does nothing and reads as though it does."
  }

  validation {
    condition     = alltrue([for item in var.items : length(item.source_url) <= 32768 && length(item.target_url) <= 32768])
    error_message = "A source_url or target_url is over Cloudflare's 32 KB limit."
  }
}

variable "max_managed_items" {
  type        = number
  default     = 500
  description = <<-EOT
    Ceiling on how many rows this module will manage, asserted before anything is
    created. Only meaningful when `manage_items` is true.

    The limit is about Terraform rather than about Cloudflare, which is happy with
    a list of hundreds of thousands. Every managed row is in state, in every plan
    and in every apply, and Cloudflare replaces the whole list each time. A few
    hundred is configuration; a redirect table is data, and belongs in a Lists API
    load step with `manage_items = false`.
  EOT

  validation {
    condition     = var.max_managed_items >= 0
    error_message = "max_managed_items must be zero or greater."
  }
}
