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
  default     = "Single redirect rules"
  description = "Display name for the single redirect ruleset (http_request_dynamic_redirect phase)."
}

variable "rules" {
  type = list(object({
    name        = string
    expression  = string
    description = optional(string)
    enabled     = optional(bool, true)

    target_url            = optional(string)
    target_url_expression = optional(string)
    status_code           = optional(number, 302)
    preserve_query_string = optional(bool, false)
  }))
  default     = []
  description = <<-EOT
    Single Redirects deployed to the http_request_dynamic_redirect phase, in
    list order. A redirect ends evaluation, so the FIRST matching rule wins:
    specific rules go before broad ones.

    Use these where a Bulk Redirect cannot do the job, most often because the
    target has to be built from the request. A Bulk Redirect sends either its
    own query string or the request's, never both. A Single Redirect can
    concat() the two.

      - `name`                  : stable label, unique within the ruleset. Used
                                  as the description when none is given.
      - `expression`            : Cloudflare Ruleset (wirefilter) expression
                                  selecting which requests are redirected.
      - `enabled`               : deploy the rule but leave it inactive when false.
      - `target_url`            : static absolute URL. Mutually exclusive with
                                  `target_url_expression`.
      - `target_url_expression` : expression evaluated per request to produce
                                  the URL, for example
                                  concat("https://example.com/?", http.request.uri.query, "&lang=en").
      - `status_code`           : 301, 302, 303, 307 or 308. Defaults to 302
                                  rather than Cloudflare's 301: browsers cache a
                                  301 indefinitely, so a mistake in a permanent
                                  redirect outlives its fix. Choose 301 on purpose.
      - `preserve_query_string` : carry the request's query string onto a static
                                  `target_url`. Leave it false when the expression
                                  already places http.request.uri.query.

    ORDERING AGAINST OTHER PHASES. This phase runs before WAF custom rules,
    managed rules and Bulk Redirects. A matching request is redirected before the
    WAF sees it, and a Single Redirect wins over any Bulk Redirect for the same
    URL.

    SECURITY. Never take the target's scheme or host from request input such as
    the query string, a header or the path. That builds an open redirect, a link
    on your domain that sends visitors anywhere an attacker chooses. Keep the
    host a literal, or http.host, and pass request data only into the target's
    path or query.
  EOT

  validation {
    condition = alltrue([
      for r in var.rules : trimspace(r.name) != "" && trimspace(r.expression) != ""
    ])
    error_message = "Each rules entry must set a non-empty `name` and `expression`."
  }

  validation {
    condition = alltrue([
      for r in var.rules : (r.target_url == null) != (r.target_url_expression == null)
    ])
    error_message = "Each rules entry must set exactly one of `target_url` or `target_url_expression`. Both is ambiguous; neither redirects to nothing."
  }

  validation {
    condition = alltrue([
      for r in var.rules : r.target_url == null || can(regex("^https?://[^/?#[:space:]]+", r.target_url))
    ])
    error_message = "rules[*].target_url must be an absolute http:// or https:// URL."
  }

  validation {
    condition = alltrue([
      for r in var.rules : r.target_url_expression == null || trimspace(r.target_url_expression) != ""
    ])
    error_message = "rules[*].target_url_expression must not be empty."
  }

  validation {
    condition = alltrue([
      for r in var.rules : contains([301, 302, 303, 307, 308], r.status_code)
    ])
    error_message = "rules[*].status_code must be one of: 301, 302, 303, 307, 308."
  }
}
