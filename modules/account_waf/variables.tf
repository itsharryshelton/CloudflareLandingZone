variable "account_id" {
  type        = string
  description = "Cloudflare Account ID that owns the account-level WAF rulesets."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zone_names" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Apex domains the account-level rules apply to, matched on cf.zone.name.
    Empty - the default - applies them to every Enterprise zone in the account,
    including zones this repository does not manage, which is the point of
    enforcing a baseline at account level.

    Whatever is listed, Cloudflare only runs account-level WAF rules on
    Enterprise zones: every execute rule this module writes ends with
    `and cf.zone.plan eq "ENT"`, which the API requires. A zone on a lower plan
    listed here is silently not covered.
  EOT

  validation {
    condition = alltrue([
      for name in var.zone_names : can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", name))
    ])
    error_message = "zone_names entries must be lowercase, fully qualified apex domains (e.g. example.com) - they are interpolated into a Cloudflare expression."
  }

  validation {
    condition     = length(distinct(var.zone_names)) == length(var.zone_names)
    error_message = "zone_names lists the same domain twice."
  }
}

variable "custom_ruleset_name" {
  type        = string
  default     = "Account WAF - Custom Rules"
  description = "Display name for the account custom ruleset (kind custom) that holds the custom rules."
}

variable "custom_entrypoint_name" {
  type        = string
  default     = "Account WAF - Custom Rules Entry Point"
  description = "Display name for the account's http_request_firewall_custom entry-point ruleset, which executes the custom ruleset."
}

variable "managed_entrypoint_name" {
  type        = string
  default     = "Account WAF - Managed Rules Entry Point"
  description = "Display name for the account's http_request_firewall_managed entry-point ruleset."
}

variable "custom_rules" {
  type = list(object({
    name        = string
    expression  = string
    action      = optional(string, "block")
    description = optional(string)
    enabled     = optional(bool, true)
    logging     = optional(bool)
    skip = optional(object({
      ruleset = optional(string)
      phases  = optional(list(string))
    }))
  }))
  default     = []
  description = <<-EOT
    Custom WAF rules held in one account custom ruleset and executed from the
    account's http_request_firewall_custom entry point.

    Same shape as the waf module's custom_block_rules, minus the legacy
    `skip.products`, which is a zone-only concept.
      - action     : block, challenge, managed_challenge, js_challenge, log or skip.
      - expression : Cloudflare Ruleset (wirefilter) expression. The Enterprise
                     zone scope is added by the execute rule, not here.
      - description: shown in the dashboard and audit logs. Falls back to `name`.
      - enabled    : deploy the rule but leave it inactive when false.
      - logging    : only on a skip rule, which Cloudflare does not log by default.
      - skip       : required when action is "skip", rejected otherwise.
                     `ruleset = "current"` stops evaluating this custom ruleset
                     only; the zone's own custom rules still run afterwards.
                     `phases` skips later phases: http_ratelimit,
                     http_request_firewall_managed or http_request_sbfm.

    Rules are evaluated in list order, and their resolved descriptions must be
    unique.
  EOT

  validation {
    condition = alltrue([
      for r in var.custom_rules :
      contains(["block", "challenge", "managed_challenge", "js_challenge", "log", "skip"], r.action)
    ])
    error_message = "custom_rules[*].action must be one of: block, challenge, managed_challenge, js_challenge, log, skip."
  }

  validation {
    condition = alltrue([
      for r in var.custom_rules : trimspace(r.name) != "" && trimspace(r.expression) != ""
    ])
    error_message = "Each custom_rules entry must set a non-empty `name` and `expression`."
  }

  validation {
    condition = alltrue([
      for r in var.custom_rules : (r.action == "skip") == (r.skip != null)
    ])
    error_message = "`skip` must be set when action is \"skip\", and omitted otherwise."
  }

  validation {
    condition = alltrue([
      for r in var.custom_rules :
      r.skip == null || try(r.skip.ruleset, null) != null || try(r.skip.phases, null) != null
    ])
    error_message = "A skip rule must say what to skip: set skip.ruleset, skip.phases or both."
  }

  validation {
    condition = alltrue([
      for r in var.custom_rules :
      try(r.skip.ruleset, null) == null || try(r.skip.ruleset, "") == "current"
    ])
    error_message = "skip.ruleset accepts only \"current\". To skip a managed ruleset, use managed_exceptions."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.custom_rules : [
        for phase in coalesce(try(r.skip.phases, null), []) :
        contains(["http_ratelimit", "http_request_firewall_managed", "http_request_sbfm"], phase)
      ]
    ]))
    error_message = "skip.phases entries must be one of: http_ratelimit, http_request_firewall_managed, http_request_sbfm."
  }

  validation {
    condition = alltrue([
      for r in var.custom_rules : r.logging == null || r.action == "skip"
    ])
    error_message = "`logging` is only settable on a skip rule. Cloudflare logs the other actions by default and rejects an explicit logging block on them."
  }
}

variable "managed_rulesets" {
  type = list(object({
    id          = string
    version     = optional(string)
    expression  = optional(string, "true")
    description = optional(string)
    enabled     = optional(bool, true)
    overrides = optional(object({
      action            = optional(string)
      enabled           = optional(bool)
      sensitivity_level = optional(string)
      categories = optional(list(object({
        category          = string
        action            = optional(string)
        enabled           = optional(bool)
        sensitivity_level = optional(string)
      })), [])
      rules = optional(list(object({
        id                = string
        action            = optional(string)
        enabled           = optional(bool)
        score_threshold   = optional(number)
        sensitivity_level = optional(string)
      })), [])
    }))
  }))
  default     = []
  description = <<-EOT
    Cloudflare-authored rulesets executed from the account's
    http_request_firewall_managed entry point, in list order. Same shape and
    override semantics as the waf module's managed_rulesets.

    `expression` narrows which traffic a ruleset runs against (default "true",
    all of it). The module appends the zone scope and the mandatory
    `cf.zone.plan eq "ENT"` clause, so do not add either here.

    These run in addition to any managed rulesets a zone executes itself. A
    ruleset executed at both levels is evaluated twice, and a zone-level
    exception cannot skip an account-level rule - put the exception in
    managed_exceptions here instead.
  EOT

  validation {
    condition = alltrue([
      for ruleset in var.managed_rulesets : can(regex("^[0-9a-f]{32}$", ruleset.id))
    ])
    error_message = "managed_rulesets[*].id must be a 32-character hexadecimal Cloudflare ruleset identifier."
  }

  validation {
    condition     = length(distinct([for ruleset in var.managed_rulesets : ruleset.id])) == length(var.managed_rulesets)
    error_message = "managed_rulesets names the same ruleset ID twice. Merge them into one entry with one set of overrides."
  }

  validation {
    condition = alltrue([
      for ruleset in var.managed_rulesets : trimspace(coalesce(ruleset.expression, "true")) != ""
    ])
    error_message = "managed_rulesets[*].expression must be a non-empty Cloudflare expression, or left unset for \"true\"."
  }

  validation {
    condition = alltrue([
      for ruleset in var.managed_rulesets : !strcontains(coalesce(ruleset.expression, "true"), "cf.zone.plan")
    ])
    error_message = "managed_rulesets[*].expression must not mention cf.zone.plan: the module appends `and cf.zone.plan eq \"ENT\"` itself, and Cloudflare requires it to be the final clause."
  }

  validation {
    condition = alltrue(flatten([
      for ruleset in var.managed_rulesets : [
        for action in concat(
          [try(ruleset.overrides.action, null)],
          [for category in try(ruleset.overrides.categories, []) : category.action],
          [for rule in try(ruleset.overrides.rules, []) : rule.action],
        ) :
        action == null || contains(["block", "challenge", "managed_challenge", "js_challenge", "log"], coalesce(action, "log"))
      ]
    ]))
    error_message = "Managed ruleset override actions must be one of: block, challenge, managed_challenge, js_challenge, log."
  }

  validation {
    condition = alltrue(flatten([
      for ruleset in var.managed_rulesets : [
        for level in concat(
          [try(ruleset.overrides.sensitivity_level, null)],
          [for category in try(ruleset.overrides.categories, []) : category.sensitivity_level],
          [for rule in try(ruleset.overrides.rules, []) : rule.sensitivity_level],
        ) :
        level == null || contains(["default", "medium", "low", "eoff"], coalesce(level, "default"))
      ]
    ]))
    error_message = "sensitivity_level must be one of: default, medium, low, eoff."
  }

  validation {
    condition = alltrue(flatten([
      for ruleset in var.managed_rulesets : [
        for rule in try(ruleset.overrides.rules, []) :
        can(regex("^[0-9a-f]{32}$", rule.id)) && (rule.score_threshold == null || (coalesce(rule.score_threshold, 1) >= 1 && coalesce(rule.score_threshold, 1) <= 100))
      ]
    ]))
    error_message = "managed_rulesets[*].overrides.rules[*].id must be a 32-character hexadecimal rule identifier, and score_threshold (if set) between 1 and 100."
  }
}

variable "managed_exceptions" {
  type = list(object({
    name        = string
    expression  = string
    description = optional(string)
    enabled     = optional(bool, true)
    logging     = optional(bool)
    skip = object({
      ruleset  = optional(string)
      rulesets = optional(list(string))
      rules    = optional(map(list(string)))
    })
  }))
  default     = []
  description = <<-EOT
    Skip rules placed at the top of the account's http_request_firewall_managed
    entry point, ahead of every managed_rulesets execute rule. Same shape as the
    waf module's managed_exceptions. This is the only place an account-level
    managed rule can be turned off for narrowly scoped traffic: a zone's own
    exceptions do not reach it.

    Pin the host, method and path. An account-level exception with a loose
    expression exempts that traffic on every Enterprise zone in scope.
  EOT

  validation {
    condition = alltrue([
      for e in var.managed_exceptions : trimspace(e.name) != "" && trimspace(e.expression) != ""
    ])
    error_message = "Each managed_exceptions entry must set a non-empty `name` and `expression`."
  }

  validation {
    condition     = length(var.managed_exceptions) == 0 || length(var.managed_rulesets) > 0
    error_message = "managed_exceptions is set but managed_rulesets is empty, so the exceptions have nothing to skip."
  }

  validation {
    condition = alltrue([
      for e in var.managed_exceptions :
      length([for target in [e.skip.ruleset, e.skip.rulesets, e.skip.rules] : target if target != null]) == 1
    ])
    error_message = "Each managed_exceptions entry must set exactly one of skip.ruleset, skip.rulesets or skip.rules."
  }

  validation {
    condition = alltrue([
      for e in var.managed_exceptions : e.skip.ruleset == null || e.skip.ruleset == "current"
    ])
    error_message = "managed_exceptions[*].skip.ruleset accepts only \"current\"."
  }

  validation {
    condition = alltrue(flatten([
      for e in var.managed_exceptions : concat(
        [e.skip.rulesets == null || length(coalesce(e.skip.rulesets, [])) > 0],
        [e.skip.rules == null || length(coalesce(e.skip.rules, {})) > 0],
        [for rule_ids in coalesce(e.skip.rules, {}) : length(rule_ids) > 0],
      )
    ]))
    error_message = "managed_exceptions[*].skip.rulesets, skip.rules and every rule list inside skip.rules must be non-empty."
  }

  validation {
    condition = alltrue(flatten([
      for e in var.managed_exceptions : [
        for id in concat(coalesce(e.skip.rulesets, []), keys(coalesce(e.skip.rules, {}))) :
        contains([for ruleset in var.managed_rulesets : ruleset.id], id)
      ]
    ]))
    error_message = "A managed_exceptions entry names a ruleset that is not in managed_rulesets, so it would match nothing."
  }

  validation {
    condition = alltrue(flatten([
      for e in var.managed_exceptions : [
        for id in flatten(values(coalesce(e.skip.rules, {}))) : can(regex("^[0-9a-f]{32}$", id))
      ]
    ]))
    error_message = "managed_exceptions rule IDs must be 32-character hexadecimal Cloudflare identifiers."
  }
}
