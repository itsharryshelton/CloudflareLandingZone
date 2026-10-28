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
  default     = "Configuration rules"
  description = "Display name for the configuration ruleset (http_config_settings phase)."
}

variable "rules" {
  type = list(object({
    name        = string
    expression  = string
    description = optional(string)
    enabled     = optional(bool, true)

    ssl = optional(string)
  }))
  default     = []
  description = <<-EOT
    Configuration Rules deployed to the http_config_settings phase, in list
    order. Each is a `set_config` action: it overrides zone settings for the
    requests its expression matches and leaves every other request on the
    zone's own settings. Every matching rule applies, so where two rules set the
    same setting the LAST one wins.

      - `name`        : stable label, unique within the ruleset. Used as the
                        description when none is given.
      - `expression`  : Cloudflare Ruleset (wirefilter) expression. For a
                        per-hostname override, http.host eq "app.example.com".
      - `enabled`     : deploy the rule but leave it inactive when false.
      - `ssl`         : SSL/TLS encryption mode for the matched requests: off,
                        flexible, full or strict. The usual reason to set it is
                        one proxied hostname whose origin cannot yet present a
                        certificate valid for its name, which strict answers
                        with a 526. Lowering the zone instead weakens every
                        hostname on it.

    Every setting is optional, but a rule must set at least one. Further
    set_config settings belong here as more optional attributes, which leaves
    existing callers untouched.

    Configuration Rules only see proxied traffic. A DNS-only record never
    reaches the edge, so no rule here changes anything for it.

    PLAN LIMITS. A zone may hold 10 configuration rules on Free, 25 on Pro, 50
    on Business and 300 on Enterprise. The ruleset is written in one request,
    so going over the limit fails the whole phase for the zone, not just the
    rules past it.

    SECURITY. Each step down from strict removes a check on the connection from
    Cloudflare to the origin, and the visitor sees the same padlock throughout:

      - full     : still encrypted, but any certificate is accepted - self-signed,
                   expired or issued for another name - so anything able to
                   intercept traffic to the origin can impersonate it.
      - flexible : plain HTTP to the origin on port 80. An origin that redirects
                   HTTP to HTTPS loops.
      - off      : no HTTPS for the visitor either.

    Scope a downgrade to the one hostname that needs it, prefer full over
    flexible, and remove the rule once the origin's certificate is valid.
  EOT

  validation {
    condition = alltrue([
      for r in var.rules : trimspace(r.name) != "" && trimspace(r.expression) != ""
    ])
    error_message = "Each rules entry must set a non-empty `name` and `expression`."
  }

  validation {
    condition     = alltrue([for r in var.rules : r.ssl != null])
    error_message = "Each rules entry must set at least one setting (currently only `ssl` is supported); a configuration rule with none matches traffic and changes nothing."
  }

  validation {
    condition = alltrue([
      for r in var.rules : r.ssl == null || contains(["off", "flexible", "full", "strict"], r.ssl)
    ])
    error_message = "rules[*].ssl must be one of: off, flexible, full, strict."
  }
}
