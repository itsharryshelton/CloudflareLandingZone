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
    logging     = optional(bool)
    skip = optional(object({
      ruleset  = optional(string)
      rulesets = optional(list(string))
      phases   = optional(list(string))
      products = optional(list(string))
    }))
  }))
  default     = []
  description = <<-EOT
    Custom WAF rules deployed to the http_request_firewall_custom phase.
      - action     : the action taken on a match. One of: block, challenge,
                     managed_challenge, js_challenge, log, skip. (v4's rule
                     schema differed; there is no "rate_limit" action here - use
                     var.rate_limiting_rules.)
      - expression : Cloudflare Ruleset (wirefilter) expression.
      - description: shown in the dashboard and audit logs. Falls back to `name`.
      - enabled    : deploy the rule but leave it inactive when false.
      - logging    : force logging on or off for this rule. Only meaningful on a
                     skip rule, where Cloudflare does not log the match by
                     default - a skip you cannot find in the Firewall Events log
                     is the default behaviour, not a fault. Leave unset elsewhere.
      - skip       : required when action is "skip", rejected otherwise.

    THE SKIP ACTION
    A skip rule turns protection OFF for the traffic it matches, which makes it
    the one rule type here that can only ever widen the attack surface. It exists
    because some legitimate traffic - a payment gateway callback, a CMS upload
    endpoint - is indistinguishable from an attack to a managed ruleset. Scope it
    as narrowly as the case allows: pin the path, the method, and where possible
    the source, rather than skipping a whole hostname.

    What to skip:
      - `ruleset`  : only "current" is valid. Stops evaluating THIS ruleset, so
                     the tenant's own later rules do not run. Does not affect
                     managed rulesets.
      - `phases`   : whole phases. Accepted here: http_ratelimit,
                     http_request_firewall_managed, http_request_sbfm. Skipping
                     http_request_firewall_managed turns off EVERY managed
                     ruleset for the request - the blunt fix for a managed rule
                     that false-positives.
      - `products` : legacy, non-ruleset products. One or more of: waf,
                     rateLimit, uaBlock, bic, hot, securityLevel, zoneLockdown.
      - `rulesets` : rejected. Cloudflare only accepts it in the phase that
                     executes the rulesets being skipped. A managed ruleset or
                     rule that false-positives is turned off with
                     var.managed_exceptions, which keeps the rest of the
                     managed rules running.

    Rules are evaluated in list order, and their resolved descriptions must be
    unique. A skip only affects what is evaluated after it, so its position in
    the list is part of its meaning.
  EOT

  validation {
    condition = alltrue([
      for r in var.custom_block_rules :
      contains(["block", "challenge", "managed_challenge", "js_challenge", "log", "skip"], r.action)
    ])
    error_message = "custom_block_rules[*].action must be one of: block, challenge, managed_challenge, js_challenge, log, skip."
  }

  validation {
    condition = alltrue([
      for r in var.custom_block_rules : trimspace(r.name) != "" && trimspace(r.expression) != ""
    ])
    error_message = "Each custom_block_rules entry must set a non-empty `name` and `expression`."
  }

  validation {
    condition = alltrue([
      for r in var.custom_block_rules : (r.action == "skip") == (r.skip != null)
    ])
    error_message = "`skip` must be set when action is \"skip\", and omitted otherwise. Cloudflare rejects a skip rule with no action parameters, and ignores skip parameters on any other action - which reads as a scoped exception while being fully active."
  }

  validation {
    condition = alltrue([
      for r in var.custom_block_rules :
      r.skip == null || anytrue([
        try(r.skip.ruleset, null) != null,
        try(r.skip.phases, null) != null,
        try(r.skip.products, null) != null,
      ])
    ])
    error_message = "A skip rule must say what to skip: set at least one of skip.ruleset, skip.phases or skip.products."
  }

  validation {
    condition = alltrue([
      for r in var.custom_block_rules :
      try(r.skip.ruleset, null) == null || try(r.skip.ruleset, "") == "current"
    ])
    error_message = "skip.ruleset accepts only \"current\". To skip a specific managed ruleset, use managed_exceptions."
  }

  # Kept in the type so dropping it is not a breaking change; it would only ever
  # fail at apply. Remove at the next major.
  validation {
    condition = alltrue([
      for r in var.custom_block_rules : try(r.skip.rulesets, null) == null
    ])
    error_message = "skip.rulesets is not accepted in http_request_firewall_custom: Cloudflare only lets a skip name specific rulesets in the phase that executes them. Use managed_exceptions to skip specific managed rulesets or rules, or skip.phases = [\"http_request_firewall_managed\"] to skip every managed ruleset for the request."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.custom_block_rules : [
        for phase in coalesce(try(r.skip.phases, null), []) :
        contains(["http_ratelimit", "http_request_firewall_managed", "http_request_sbfm"], phase)
      ]
    ]))
    error_message = "skip.phases entries must be one of: http_ratelimit, http_request_firewall_managed, http_request_sbfm. Those are the phases evaluated after http_request_firewall_custom, so they are the only ones a rule here can skip."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.custom_block_rules : [
        for product in coalesce(try(r.skip.products, null), []) :
        contains(["waf", "rateLimit", "uaBlock", "bic", "hot", "securityLevel", "zoneLockdown"], product)
      ]
    ]))
    error_message = "skip.products entries must be one of: waf, rateLimit, uaBlock, bic, hot, securityLevel, zoneLockdown. Note the camelCase - Cloudflare rejects rate_limit and ua_block."
  }

  validation {
    condition = alltrue([
      for r in var.custom_block_rules : r.logging == null || r.action == "skip"
    ])
    error_message = "`logging` is only settable on a skip rule. Cloudflare logs the other actions by default and rejects an explicit logging block on them."
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

variable "managed_ruleset_name" {
  type        = string
  default     = "Enterprise WAF - Managed Rules"
  description = "Display name for the managed rules ruleset (http_request_firewall_managed phase)."
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
    Cloudflare-authored rulesets executed in the http_request_firewall_managed
    phase, in list order. These are the "Managed Rules" of the dashboard rather
    than custom rules: Cloudflare owns the rules inside each ruleset and keeps
    them current, and this module only decides which ones run, against what
    traffic, and how their verdicts are retuned.

    Well-known ruleset IDs, which are global constants and the same in every
    account:
      - efb7b8c949ac4650a09736fc376e9aee - Cloudflare Managed Ruleset
      - 4814384a9e5d4991b9815dcfc25d2f1f - Cloudflare OWASP Core Ruleset
      - 77454fe2d30c4220b5701f6fdfb893ba - Cloudflare Free Managed Ruleset
    The first two need Pro or above. Cloudflare rejects the entire entry-point
    ruleset when the zone is not entitled to one it names, so one unentitled
    ruleset takes the others down with it.

    - `id`          - The managed ruleset's ID.
    - `version`     - (Optional) Pin a ruleset version. Unset tracks latest, which
                      is the point of a managed ruleset - pin only to freeze a
                      zone during an incident, and unpin afterwards.
    - `expression`  - (Optional) Which traffic the ruleset is executed against.
                      Defaults to "true", meaning all of it. Narrowing this is how
                      a ruleset is scoped to one hostname or path.
    - `description` - (Optional) Shown in the dashboard and in audit logs.
                      Descriptions must be unique within the ruleset.
    - `enabled`     - (Optional) Deploy the execute rule but leave it inactive.

    OVERRIDES
    An override retunes rules Cloudflare already ships. It cannot add a rule and
    it cannot change what a rule matches. They apply most-specific-wins:
    ruleset-level, then category (tag), then individual rule.

      - `action`            - Force this action on every rule in the ruleset.
                              Unset leaves each rule on Cloudflare's own default,
                              which is what you want unless the ruleset is
                              deliberately being run in monitoring mode ("log").
      - `enabled`           - Turn the whole ruleset's rules on or off.
      - `sensitivity_level` - default, medium, low or eoff. Meaningful on the
                              Cloudflare Managed Ruleset; the OWASP ruleset uses a
                              score threshold instead.
      - `categories`        - Per-tag overrides, e.g. disabling "paranoia-level-3".
                              A tag override also covers rules Cloudflare adds to
                              that tag later, which a per-rule override does not.
      - `rules`             - Per-rule overrides by rule ID. `score_threshold` is
                              only meaningful on the OWASP anomaly rule
                              (6179ae15870a4bb7b2d480d4843b323c), where 60, 40 and
                              25 are Cloudflare's low, medium and high
                              sensitivities - a LOWER number blocks more traffic.

    Turning a managed rule off for one endpoint is not done here: that is an
    exception, in var.managed_exceptions.
  EOT

  validation {
    condition = alltrue([
      for ruleset in var.managed_rulesets : can(regex("^[0-9a-f]{32}$", ruleset.id))
    ])
    error_message = "managed_rulesets[*].id must be a 32-character hexadecimal Cloudflare ruleset identifier."
  }

  validation {
    condition     = length(distinct([for ruleset in var.managed_rulesets : ruleset.id])) == length(var.managed_rulesets)
    error_message = "managed_rulesets names the same ruleset ID twice. Cloudflare evaluates both, the second silently overriding the first's verdict, and the dashboard shows two identical entries - merge them into one entry with one set of overrides."
  }

  validation {
    condition = alltrue([
      for ruleset in var.managed_rulesets : trimspace(coalesce(ruleset.expression, "true")) != ""
    ])
    error_message = "managed_rulesets[*].expression must be a non-empty Cloudflare expression, or left unset for \"true\"."
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
    error_message = "Managed ruleset override actions must be one of: block, challenge, managed_challenge, js_challenge, log. \"skip\" is not one of them - an exception to a managed ruleset belongs in managed_exceptions."
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
    error_message = "sensitivity_level must be one of: default, medium, low, eoff (\"eoff\" meaning off entirely)."
  }

  validation {
    condition = alltrue(flatten([
      for ruleset in var.managed_rulesets : [
        for rule in try(ruleset.overrides.rules, []) : can(regex("^[0-9a-f]{32}$", rule.id))
      ]
    ]))
    error_message = "managed_rulesets[*].overrides.rules[*].id must be a 32-character hexadecimal Cloudflare rule identifier."
  }

  validation {
    condition = alltrue(flatten([
      for ruleset in var.managed_rulesets : [
        for rule in try(ruleset.overrides.rules, []) :
        rule.score_threshold == null || (rule.score_threshold >= 1 && rule.score_threshold <= 100)
      ]
    ]))
    error_message = "score_threshold must be between 1 and 100. Cloudflare's published OWASP sensitivities are 60 (low), 40 (medium) and 25 (high); a lower threshold blocks more traffic and produces more false positives."
  }

  validation {
    condition = alltrue(flatten([
      for ruleset in var.managed_rulesets : [
        for category in try(ruleset.overrides.categories, []) : trimspace(category.category) != ""
      ]
    ]))
    error_message = "managed_rulesets[*].overrides.categories[*].category must be a non-empty Cloudflare rule tag (e.g. \"paranoia-level-2\", \"wordpress\")."
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
    WAF exceptions: skip rules placed at the top of the
    http_request_firewall_managed entry point, ahead of every managed_rulesets
    execute rule. This is how a managed rule that false-positives on one
    endpoint is turned off for that endpoint and nowhere else.

    It has to be this phase. A skip rule in custom_block_rules can only skip the
    managed phase as a whole; Cloudflare accepts a skip naming individual
    rulesets or rules only in the phase that executes them, and it only affects
    the execute rules listed after it - which is why these always go first.

    - `name`        - Label, used as the description when that is unset.
    - `expression`  - Which requests the exception covers. Pin the host, the
                      method and the path rather than exempting a whole
                      hostname: everything this matches loses the protection
                      being skipped.
    - `description` - (Optional) Shown in the dashboard and audit logs. Must be
                      unique across this entry point, execute rules included.
    - `enabled`     - (Optional) Deploy the exception but leave it inactive.
    - `logging`     - (Optional) Log requests the exception matches. Unset
                      leaves Cloudflare's default.
    - `skip`        - What to skip. Exactly one of:
        - `ruleset`  : "current" - every managed ruleset executed after this.
        - `rulesets` : managed ruleset IDs, each skipped whole.
        - `rules`    : managed ruleset ID => IDs of rules in that ruleset. The
                       narrowest option and the one to prefer, because the rest
                       of the ruleset keeps protecting the endpoint. Rule IDs
                       come from the Security Events log.

    Every ruleset an exception names must also be in managed_rulesets. A zone
    exception cannot reach anything this entry point does not execute - account
    level managed rulesets included - so one naming anything else would match
    nothing while reading as if it did.
  EOT

  validation {
    condition = alltrue([
      for e in var.managed_exceptions : trimspace(e.name) != "" && trimspace(e.expression) != ""
    ])
    error_message = "Each managed_exceptions entry must set a non-empty `name` and `expression`."
  }

  validation {
    condition     = length(var.managed_exceptions) == 0 || length(var.managed_rulesets) > 0
    error_message = "managed_exceptions is set but managed_rulesets is empty. An exception only skips managed rulesets this module executes, so with none it has nothing to act on."
  }

  # Cloudflare treats the three as alternative forms of the skip, not as options
  # that combine.
  validation {
    condition = alltrue([
      for e in var.managed_exceptions :
      length([for target in [e.skip.ruleset, e.skip.rulesets, e.skip.rules] : target if target != null]) == 1
    ])
    error_message = "Each managed_exceptions entry must set exactly one of skip.ruleset, skip.rulesets or skip.rules. To skip whole rulesets and individual rules for the same traffic, write two exceptions."
  }

  validation {
    condition = alltrue([
      for e in var.managed_exceptions : e.skip.ruleset == null || e.skip.ruleset == "current"
    ])
    error_message = "managed_exceptions[*].skip.ruleset accepts only \"current\", which skips every managed ruleset executed after the exception."
  }

  validation {
    condition = alltrue(flatten([
      for e in var.managed_exceptions : concat(
        [e.skip.rulesets == null || length(coalesce(e.skip.rulesets, [])) > 0],
        [e.skip.rules == null || length(coalesce(e.skip.rules, {})) > 0],
        [for rule_ids in coalesce(e.skip.rules, {}) : length(rule_ids) > 0],
      )
    ]))
    error_message = "managed_exceptions[*].skip.rulesets, skip.rules and every rule list inside skip.rules must be non-empty. Cloudflare rejects an empty skip target rather than treating it as matching nothing."
  }

  validation {
    condition = alltrue(flatten([
      for e in var.managed_exceptions : [
        for id in concat(
          coalesce(e.skip.rulesets, []),
          keys(coalesce(e.skip.rules, {})),
          flatten(values(coalesce(e.skip.rules, {}))),
        ) : can(regex("^[0-9a-f]{32}$", id))
      ]
    ]))
    error_message = "managed_exceptions ruleset and rule IDs must be 32-character hexadecimal Cloudflare identifiers."
  }

  validation {
    condition = alltrue(flatten([
      for e in var.managed_exceptions : [
        for id in concat(coalesce(e.skip.rulesets, []), keys(coalesce(e.skip.rules, {}))) :
        contains([for ruleset in var.managed_rulesets : ruleset.id], id)
      ]
    ]))
    error_message = "A managed_exceptions entry names a ruleset that is not in managed_rulesets. A zone exception only skips rulesets this entry point executes, so it would match nothing."
  }
}
