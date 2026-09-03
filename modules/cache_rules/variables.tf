variable "zone_id" {
  type        = string
  description = "Target Cloudflare Zone ID (typically module.zone_base.zone_id)."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hexadecimal Cloudflare zone identifier."
  }
}

variable "ruleset_name" {
  type        = string
  default     = "Cache rules"
  description = "Display name for the cache ruleset (http_request_cache_settings phase)."
}

variable "rules" {
  type = list(object({
    name        = string
    expression  = string
    description = optional(string)
    enabled     = optional(bool, true)

    cache = optional(bool)

    cache_key = optional(object({
      cache_by_device_type       = optional(bool)
      cache_deception_armor      = optional(bool)
      ignore_query_strings_order = optional(bool)

      custom_key = optional(object({
        query_string = optional(object({
          include = optional(object({
            all  = optional(bool)
            list = optional(list(string))
          }))
          exclude = optional(object({
            all  = optional(bool)
            list = optional(list(string))
          }))
        }))
        host = optional(object({
          resolved = optional(bool)
        }))
        header = optional(object({
          include        = optional(list(string))
          check_presence = optional(list(string))
          contains       = optional(map(list(string)))
          exclude_origin = optional(bool)
        }))
        cookie = optional(object({
          include        = optional(list(string))
          check_presence = optional(list(string))
        }))
        user = optional(object({
          device_type = optional(bool)
          geo         = optional(bool)
          lang        = optional(bool)
        }))
      }))
    }))

    edge_ttl = optional(object({
      mode    = string
      default = optional(number)
      status_code_ttl = optional(list(object({
        value       = number
        status_code = optional(number)
        status_code_range = optional(object({
          from = optional(number)
          to   = optional(number)
        }))
      })))
    }))

    browser_ttl = optional(object({
      mode    = string
      default = optional(number)
    }))

    serve_stale = optional(object({
      disable_stale_while_updating = optional(bool)
    }))

    respect_strong_etags       = optional(bool)
    origin_cache_control       = optional(bool)
    origin_error_page_passthru = optional(bool)
    read_timeout               = optional(number)
  }))
  default     = []
  description = <<-EOT
    Cache rules deployed to the http_request_cache_settings phase, in list order.
    Every rule is a `set_cache_settings` action; what differs is which settings
    it carries.

    ORDER IS THE WHOLE GAME. Cloudflare evaluates this phase top to bottom and
    the LAST matching rule wins, so a broad "cache everything" rule placed after
    a narrow "do not cache /admin" rule silently re-enables caching on /admin.
    Write the broad rules first and the exceptions after them.

      - `name`        : stable label. Used as the description when none is given,
                        and must be unique within the ruleset.
      - `expression`  : Cloudflare Ruleset (wirefilter) expression.
      - `enabled`     : deploy the rule but leave it inactive when false.
      - `cache`       : true forces the response cacheable, false bypasses cache
                        entirely. Leave unset to keep Cloudflare's default
                        eligibility and only adjust TTLs or the cache key.
      - `cache_key`   : which parts of the request distinguish one cached object
                        from another. The common case is folding every query
                        string variant onto one object:
                          cache_key = { custom_key = { query_string = { exclude = { all = true } } } }
                        Beware the inverse: including a high-cardinality
                        parameter fragments the cache and can be worse than not
                        caching at all.
      - `edge_ttl`    : mode is respect_origin | override_origin | bypass_by_default.
                        `default` is seconds and is only meaningful with
                        override_origin.
      - `browser_ttl` : mode is respect_origin | override_origin | bypass_by_default | bypass.
      - the remaining flags map straight onto the Cloudflare action parameters of
        the same name.

    SECURITY. A cache rule decides what Cloudflare stores and serves to other
    visitors. Caching a response that varies per user - anything behind a session
    cookie, an Authorization header, or a signed download token - leaks one
    user's data to the next. Gate on the session cookie in the expression (see
    the note on `cache` above), or bypass those paths outright.
  EOT

  validation {
    condition = alltrue([
      for r in var.rules : trimspace(r.name) != "" && trimspace(r.expression) != ""
    ])
    error_message = "Each rules entry must set a non-empty `name` and `expression`."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.edge_ttl == null || contains(
        ["respect_origin", "override_origin", "bypass_by_default"],
        try(r.edge_ttl.mode, ""),
      )
    ])
    error_message = "rules[*].edge_ttl.mode must be one of: respect_origin, override_origin, bypass_by_default."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.browser_ttl == null || contains(
        ["respect_origin", "override_origin", "bypass_by_default", "bypass"],
        try(r.browser_ttl.mode, ""),
      )
    ])
    error_message = "rules[*].browser_ttl.mode must be one of: respect_origin, override_origin, bypass_by_default, bypass."
  }

  validation {
    # override_origin without a TTL is accepted by the schema and then rejected
    # by the API, which is a slow way to find a typo.
    condition = alltrue([
      for r in var.rules :
      try(r.edge_ttl.mode, "") != "override_origin" || try(r.edge_ttl.default, null) != null
    ])
    error_message = "rules[*].edge_ttl.mode = \"override_origin\" requires `default` (the TTL in seconds); overriding the origin with nothing to override it to is not a valid instruction."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      try(r.browser_ttl.mode, "") != "override_origin" || try(r.browser_ttl.default, null) != null
    ])
    error_message = "rules[*].browser_ttl.mode = \"override_origin\" requires `default` (the TTL in seconds)."
  }
}
