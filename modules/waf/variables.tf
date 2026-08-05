variable "zone_id" {
  type        = string
  description = "Target Cloudflare Zone ID (typically module.zone_base.zone_id)."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hexadecimal Cloudflare zone identifier."
  }
}

variable "custom_ruleset_name" {
  type        = string
  default     = "Enterprise WAF - Custom Rules"
  description = "Display name for the custom firewall ruleset (http_request_firewall_custom phase)."
}

variable "rate_limit_ruleset_name" {
  type        = string
  default     = "Enterprise WAF - Rate Limiting"
  description = "Display name for the rate limiting ruleset (http_ratelimit phase)."
}

variable "custom_block_rules" {
  type = list(object({
    name        = string
    expression  = string
    action      = optional(string, "block")
    description = optional(string)
    enabled     = optional(bool, true)
  }))
  default     = []
  description = <<-EOT
    Custom WAF rules deployed to the http_request_firewall_custom phase.
      - action     : the mitigation action. One of: block, challenge,
                     managed_challenge, js_challenge, log. (v4's rule schema
                     differed; there is no "rate_limit" action here - use
                     var.rate_limiting_rules. The "skip" action is deliberately
                     not offered: it requires action_parameters, which this
                     module does not model yet.)
      - expression : Cloudflare Ruleset (wirefilter) expression.
      - description: shown in the dashboard and audit logs. Falls back to `name`.
      - enabled    : deploy the rule but leave it inactive when false.
    Rules are evaluated in list order, and their resolved descriptions must be
    unique.
  EOT

  validation {
    condition = alltrue([
      for r in var.custom_block_rules :
      contains(["block", "challenge", "managed_challenge", "js_challenge", "log"], r.action)
    ])
    error_message = "custom_block_rules[*].action must be one of: block, challenge, managed_challenge, js_challenge, log. (\"skip\" needs action_parameters and is not supported by this module.)"
  }

  validation {
    condition = alltrue([
      for r in var.custom_block_rules : trimspace(r.name) != "" && trimspace(r.expression) != ""
    ])
    error_message = "Each custom_block_rules entry must set a non-empty `name` and `expression`."
  }
}

variable "rate_limiting_rules" {
  type = list(object({
    name                = string
    expression          = string
    period              = number
    requests            = number
    mitigation_action   = optional(string, "block")
    mitigation_timeout  = optional(number)
    characteristics     = optional(list(string), ["ip.src"])
    counting_expression = optional(string)
    requests_to_origin  = optional(bool, false)
    enabled             = optional(bool, true)
  }))
  default     = []
  description = <<-EOT
    Rate limiting rules deployed to the http_ratelimit phase.
      - period            : sampling window in seconds. One of 10, 60, 120, 300, 600, 3600.
      - requests          : max requests allowed per period (maps to the v5
                            provider field requests_per_period; replaces v4's
                            score_per_period).
      - mitigation_action : action once the limit is exceeded. One of: block,
                            challenge, managed_challenge, js_challenge, log.
      - mitigation_timeout: seconds the action stays applied after the limit is
                            hit. Defaults to `period`. Forced to 0 when
                            mitigation_action = "log", which is the only value
                            Cloudflare accepts for that action.
      - characteristics   : rate-limit grouping keys. Defaults to ["ip.src"].
      - counting_expression: optional separate expression used for counting
                            (e.g. count only origin errors).
      - requests_to_origin: count only requests that reach the origin (cache
                            misses) rather than all requests at the edge.
      - enabled           : deploy the rule but leave it inactive when false.
    Rules are evaluated in list order, and their names must be unique.
  EOT

  validation {
    condition = alltrue([
      for r in var.rate_limiting_rules : contains([10, 60, 120, 300, 600, 3600], r.period)
    ])
    error_message = "rate_limiting_rules[*].period must be one of: 10, 60, 120, 300, 600, 3600 (seconds)."
  }

  validation {
    condition = alltrue([
      for r in var.rate_limiting_rules :
      contains(["block", "challenge", "managed_challenge", "js_challenge", "log"], r.mitigation_action)
    ])
    error_message = "rate_limiting_rules[*].mitigation_action must be one of: block, challenge, managed_challenge, js_challenge, log."
  }

  validation {
    condition = alltrue([
      for r in var.rate_limiting_rules : r.requests > 0
    ])
    error_message = "rate_limiting_rules[*].requests must be greater than 0."
  }

  validation {
    condition = alltrue([
      for r in var.rate_limiting_rules : trimspace(r.name) != "" && trimspace(r.expression) != ""
    ])
    error_message = "Each rate_limiting_rules entry must set a non-empty `name` and `expression`."
  }

  validation {
    condition = alltrue([
      for r in var.rate_limiting_rules : length(r.characteristics) > 0
    ])
    error_message = "rate_limiting_rules[*].characteristics must contain at least one grouping key (e.g. [\"ip.src\"])."
  }

  validation {
    condition = alltrue([
      for r in var.rate_limiting_rules :
      r.mitigation_timeout == null || (r.mitigation_timeout >= 0 && r.mitigation_timeout <= 86400)
    ])
    error_message = "rate_limiting_rules[*].mitigation_timeout must be between 0 and 86400 seconds."
  }

  # Rather than silently discarding a value the operator set, reject the
  # combination Cloudflare will not accept.
  validation {
    condition = alltrue([
      for r in var.rate_limiting_rules :
      r.mitigation_action != "log" || coalesce(r.mitigation_timeout, 0) == 0
    ])
    error_message = "rate_limiting_rules with mitigation_action = \"log\" must leave mitigation_timeout unset or 0; Cloudflare accepts no other value for a log-only rate limit."
  }
}
