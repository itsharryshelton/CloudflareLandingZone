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

variable "bot_traffic" {
  type = object({
    search             = optional(string)
    agent              = optional(string)
    training           = optional(string)
    category_overrides = optional(map(list(string)), {})
    enabled            = optional(bool, true)
  })
  default     = null
  description = <<-EOT
    Per-behaviour handling of verified bot traffic, emitted as rules at the TOP
    of the http_request_firewall_custom ruleset - before the baseline and tenant
    rules, so that an allow can take effect.

    This lives in the waf module rather than in zone_rules because Cloudflare
    permits exactly one entry-point ruleset per phase per zone, and this module
    owns that phase. The coarse, zone-level controls (Bot Fight Mode, Super Bot
    Fight Mode, ai_bots_protection) are in ../zone_rules.

    Behaviours, using Cloudflare's current AI bot taxonomy:
      - `search`   - indexes content so it can answer questions about it later.
      - `agent`    - acts in real time on a person's behalf (chat fetch bots,
                     browser-use agents).
      - `training` - crawls content to train or fine-tune a model.

    Each takes an action, or is left unset to be ignored entirely:
      allow | log | managed_challenge | js_challenge | challenge | block

    "allow" is emitted as a `skip` rule scoped to this ruleset, which is what
    letting a bot through actually means at the edge - it stops evaluation
    before the tenant's own block rules see the request.

    Limits worth knowing before relying on this:
      - It matches VERIFIED bots only. An AI crawler that does not identify
        itself, or spoofs a user agent, has no cf.verified_bot_category and is
        not touched by these rules. Use `ai_bots_protection` in the zone_rules
        module for that traffic.
      - cf.verified_bot_category is a Bot Management field. Cloudflare publishes
        no plan floor for it, but the neighbouring cf.bot_management.* fields
        require Enterprise with Bot Management. If the zone lacks entitlement
        the ruleset is rejected at apply time, not at plan.

    - `category_overrides` - (Optional) Replace the cf.verified_bot_category
                             values a behaviour matches, keyed by behaviour.
                             Defaults are in locals.tf. Use this when Cloudflare
                             adds a category before this module does.
    - `enabled`            - (Optional) Deploy the bot rules but leave them
                             inactive. Defaults to true.
  EOT

  validation {
    condition = alltrue([
      for action in [
        try(var.bot_traffic.search, null),
        try(var.bot_traffic.agent, null),
        try(var.bot_traffic.training, null),
      ] :
      action == null || contains(
        ["allow", "log", "managed_challenge", "js_challenge", "challenge", "block"],
        coalesce(action, "allow"),
      )
    ])
    error_message = "bot_traffic.search, .agent and .training must each be one of: allow, log, managed_challenge, js_challenge, challenge, block - or left unset to leave that behaviour alone."
  }

  validation {
    condition = alltrue([
      for behaviour in keys(try(var.bot_traffic.category_overrides, {})) :
      contains(["search", "agent", "training"], behaviour)
    ])
    error_message = "bot_traffic.category_overrides keys must be one of: search, agent, training."
  }

  validation {
    condition = alltrue(flatten([
      for behaviour, categories in try(var.bot_traffic.category_overrides, {}) : [
        for category in categories : trimspace(category) != "" && !strcontains(category, "\"")
      ]
    ]))
    error_message = "bot_traffic.category_overrides values must be non-empty category names without double quotes - they are interpolated into a Cloudflare expression."
  }

  validation {
    # The behaviour is looked up through a uniformly-typed map rather than by
    # indexing var.bot_traffic directly: that object mixes strings, a map and a
    # bool, so Terraform cannot index it with a computed key.
    condition = alltrue([
      for behaviour in keys(try(var.bot_traffic.category_overrides, {})) :
      contains([
        for name, action in {
          search   = try(var.bot_traffic.search, null)
          agent    = try(var.bot_traffic.agent, null)
          training = try(var.bot_traffic.training, null)
        } : name if action != null
      ], behaviour)
    ])
    error_message = "bot_traffic.category_overrides names a behaviour that has no action set. Overriding the categories of a behaviour that is not being acted on has no effect and is more likely a typo."
  }
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
