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
  default     = "Request header transform rules"
  description = "Display name for the request header ruleset (http_request_late_transform phase)."
}

variable "rules" {
  type = list(object({
    name        = string
    expression  = string
    description = optional(string)
    enabled     = optional(bool, true)
    headers = map(object({
      operation  = string
      value      = optional(string)
      expression = optional(string)
    }))
  }))
  default     = []
  description = <<-EOT
    Request header modifications deployed to the http_request_late_transform
    phase, in list order.

    LATE, not early: this phase runs after Cloudflare's own security phases have
    decided what to do with the request, so a header set here cannot be used to
    dodge a WAF rule - and equally, a WAF rule cannot match on it. If a rule
    needs to match the header, it belongs in the early transform phase, which
    this module does not own.

    These headers reach the ORIGIN. They are not response headers and are not
    visible to the browser.

      - `name`       : stable label, unique within the ruleset. Used as the
                       description when none is given.
      - `expression` : Cloudflare Ruleset (wirefilter) expression selecting which
                       requests are rewritten.
      - `enabled`    : deploy the rule but leave it inactive when false.
      - `headers`    : map of header name => operation. Cloudflare keys this by
                       header name, so one rule cannot do two things to the same
                       header.
          operation  : set | add | remove.
                       `set` replaces any existing value, `add` appends another
                       instance, `remove` deletes the header.
          value      : literal value. Required for set and add unless
                       `expression` is used instead.
          expression : a Cloudflare expression evaluated per request to produce
                       the value. Mutually exclusive with `value`.

    SECURITY. Two things worth stating plainly:

      - Do NOT put an API key, shared secret or bearer token in `value`. It is
        stored in plain text in Terraform state and printed in every plan, so it
        ends up in state storage, in CI logs and in pull request output. Origin
        authentication belongs in mTLS or Cloudflare Tunnel, neither of which
        puts a credential in this file.
      - `remove` on a header the origin trusts for identity - Forwarded,
        X-Forwarded-For, CF-Connecting-IP - changes what the application believes
        the client IP is. That is sometimes exactly the point (stripping a header
        a client could have forged), but it also breaks rate limiting and audit
        logging at the origin if the application was reading it.
  EOT

  validation {
    condition = alltrue([
      for r in var.rules : trimspace(r.name) != "" && trimspace(r.expression) != ""
    ])
    error_message = "Each rules entry must set a non-empty `name` and `expression`."
  }

  validation {
    condition = alltrue([
      for r in var.rules : length(r.headers) > 0
    ])
    error_message = "Each rules entry must modify at least one header; a rewrite rule with an empty `headers` map matches traffic and does nothing."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.rules : [
        for h in values(r.headers) : contains(["set", "add", "remove"], h.operation)
      ]
    ]))
    error_message = "rules[*].headers[*].operation must be one of: set, add, remove."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.rules : [
        for h in values(r.headers) :
        h.operation == "remove" || (h.value == null) != (h.expression == null)
      ]
    ]))
    error_message = "A `set` or `add` header must supply exactly one of `value` or `expression`. Supplying both is ambiguous and supplying neither writes an empty header."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.rules : [
        for h in values(r.headers) :
        h.operation != "remove" || (h.value == null && h.expression == null)
      ]
    ]))
    error_message = "A `remove` header must not supply `value` or `expression`; Cloudflare rejects the rule, and the presence of a value suggests the operation was meant to be `set`."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.rules : [
        for name in keys(r.headers) : can(regex("^[A-Za-z0-9-]+$", name))
      ]
    ]))
    error_message = "Header names must contain only letters, digits and hyphens. The map key is the header name itself - there is no separate `name` field in the v5 provider."
  }
}
