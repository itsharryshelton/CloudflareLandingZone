# Layer: waf - inputs.
#
# Config files:
#   accounts/<account>/zones.tfvars - the zone inventory, shared with every layer
#   accounts/<account>/waf.tfvars   - WAF policies, consumed only here

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Scopes the zone lookup in zone_lookup.tf."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: logical key => domain name. The same file the zones layer is
    given, so the keys mean the same thing in both.

    This layer does not create zones. It looks each domain up by name to get its
    ID (see zone_lookup.tf), which is what keeps the two layers' states
    independent.

    - `domain_name` - The apex domain (e.g. example.com).
    - `zone_tier`   - (Optional) The zone's Cloudflare rate plan. Defaults to
                      var.default_zone_tier. Read here to gate `bot_traffic`,
                      which depends on Bot Management fields that lower plans do
                      not expose. This layer never changes a plan - only the
                      zones layer can do that.
  EOT
  type = map(object({
    domain_name = string
    zone_tier   = optional(string)
  }))

  validation {
    condition     = alltrue([for key in keys(var.zones) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "zones keys must be lowercase alphanumeric with underscores."
  }

  validation {
    condition = alltrue([
      for zone in var.zones : zone.zone_tier == null || contains([
        "free", "lite", "pro", "pro_plus", "business", "enterprise",
        "partners_free", "partners_pro", "partners_business",
        "partners_enterprise", "partners_ent",
      ], coalesce(zone.zone_tier, "free"))
    ])
    error_message = "zones[*].zone_tier must be one of: free, lite, pro, pro_plus, business, enterprise, partners_free, partners_pro, partners_business, partners_enterprise, partners_ent."
  }
}

variable "default_zone_tier" {
  type        = string
  default     = "free"
  description = "Rate plan assumed for a zone whose inventory entry does not name one. Must match what the zones layer was given, or bot traffic gating here will not agree with the gating there."

  validation {
    condition = contains([
      "free", "lite", "pro", "pro_plus", "business", "enterprise",
      "partners_free", "partners_pro", "partners_business",
      "partners_enterprise", "partners_ent",
    ], var.default_zone_tier)
    error_message = "default_zone_tier must be one of: free, lite, pro, pro_plus, business, enterprise, partners_free, partners_pro, partners_business, partners_enterprise, partners_ent."
  }
}

variable "bot_traffic_min_tier" {
  type        = string
  default     = "pro"
  description = <<-EOT
    Lowest rate plan allowed to carry `bot_traffic` rules. A policy that sets
    bot_traffic on a zone below this fails the plan.

    Pro by default, and it is a judgement call rather than a documented
    threshold. Cloudflare publishes no plan floor for cf.verified_bot_category,
    but the neighbouring cf.bot_management.* fields require Enterprise with Bot
    Management, and verified bot handling below Pro is Bot Fight Mode, which has
    no per-category concept at all. If your account's entitlement differs,
    change this rather than working around it - being wrong in either direction
    only costs a plan-time error instead of an apply-time one.
  EOT

  validation {
    condition = contains([
      "free", "lite", "pro", "pro_plus", "business", "enterprise",
      "partners_free", "partners_pro", "partners_business",
      "partners_enterprise", "partners_ent",
    ], var.bot_traffic_min_tier)
    error_message = "bot_traffic_min_tier must be a valid Cloudflare rate plan ID."
  }
}

variable "waf_policies" {
  description = <<-EOT
    A map of WAF policies, one per zone that needs custom firewall or rate
    limiting rules, keyed by a logical key. A zone with no policy gets no rulesets
    at all, which costs nothing.

    - `zone_key`                - The key of the zone this policy binds to. Taken from `var.zones`.
    - `bot_traffic`             - (Optional) Per-behaviour handling of verified bot traffic:
                                  `search`, `agent` and `training`, each one of allow, log,
                                  managed_challenge, js_challenge, challenge or block.
                                  Emitted as rules at the TOP of the custom ruleset, before
                                  the baseline and tenant rules, so an allow can short-circuit
                                  them. Requires a zone tier of at least
                                  var.bot_traffic_min_tier.

                                  This is in the waf layer, not the zones layer, because
                                  Cloudflare allows one entry-point ruleset per phase per
                                  zone and this layer owns http_request_firewall_custom. The
                                  coarse zone-level controls (Bot Fight Mode, Super Bot Fight
                                  Mode, ai_bots_protection) are `bot_management` in the zones
                                  layer's dns.tfvars.

                                  Matches VERIFIED bots only. An AI crawler that hides what
                                  it is has no category and is unaffected - use
                                  ai_bots_protection in the zones layer for that.
    - `baseline_custom_rules`   - (Optional) Names of baseline rules from the platform
                                  catalogue in locals.waf.tf.
    - `baseline_rate_limits`    - (Optional) Names of baseline rate limits from the same catalogue.
    - `baseline_managed_rulesets` - (Optional) Names of Cloudflare-authored managed
                                  rulesets from the catalogue in locals.waf.tf -
                                  currently `cloudflare_managed` and `owasp_core`.
                                  These land under "Managed rules" in the dashboard,
                                  not under custom rules, and are evaluated in a
                                  later phase than everything else in this policy.
                                  Both need a zone tier of at least
                                  var.managed_rules_min_tier; Cloudflare rejects
                                  the whole entry-point ruleset when the zone is
                                  not entitled to one it names. Tuned by
                                  waf_owasp_paranoia_level, waf_owasp_score_threshold,
                                  waf_owasp_action and waf_managed_rules_action.
    - `managed_rulesets`        - (Optional) Managed rulesets named by raw Cloudflare
                                  ruleset ID, appended after the baseline ones. Use
                                  this for a ruleset the catalogue does not carry
                                  (an application-specific one such as Drupal or
                                  WordPress); anything the whole estate should run
                                  belongs in the catalogue instead.
    - `custom_block_rules`      - (Optional) Tenant-specific firewall rules, appended after
                                  the baseline rules so they evaluate later. Actions are
                                  block, challenge, managed_challenge, js_challenge, log and
                                  skip. A skip rule needs a `skip` block naming what to stop
                                  evaluating, and turns protection OFF for whatever it
                                  matches - scope it to a path and a method, not to a
                                  hostname. Note the ordering: these are appended after the
                                  baseline, so a skip here cannot undo a baseline block that
                                  has already fired.
    - `rate_limiting_rules`     - (Optional) Tenant-specific rate limits, appended after the
                                  baseline rate limits.
    - `custom_ruleset_name`     - (Optional) Dashboard display name for the custom ruleset.
    - `rate_limit_ruleset_name` - (Optional) Dashboard display name for the rate limit ruleset.
    - `managed_ruleset_name`    - (Optional) Dashboard display name for the managed rules ruleset.

    Baseline rules are parameterised by `waf_trusted_ip_ranges`, `waf_admin_paths`
    and `waf_blocked_countries` rather than hardcoded, so the catalogue serves
    every customer.
  EOT
  type = map(object({
    zone_key                  = string
    baseline_custom_rules     = optional(list(string), [])
    baseline_rate_limits      = optional(list(string), [])
    baseline_managed_rulesets = optional(list(string), [])
    custom_ruleset_name       = optional(string)
    rate_limit_ruleset_name   = optional(string)
    managed_ruleset_name      = optional(string)
    bot_traffic = optional(object({
      search             = optional(string)
      agent              = optional(string)
      training           = optional(string)
      category_overrides = optional(map(list(string)), {})
      enabled            = optional(bool, true)
    }))
    custom_block_rules = optional(list(object({
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
    })), [])
    rate_limiting_rules = optional(list(object({
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
    })), [])
    managed_rulesets = optional(list(object({
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
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.waf_policies) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "waf_policies keys must be lowercase alphanumeric with underscores."
  }

  validation {
    condition     = length(distinct([for p in var.waf_policies : p.zone_key])) == length(var.waf_policies)
    error_message = "Two waf_policies entries target the same zone_key. Cloudflare allows one entry-point ruleset per phase per zone, so the second would fight the first - merge them into one policy."
  }
}

# Baseline rule parameters (defaults.auto.tfvars here, overridden per account)
variable "waf_trusted_ip_ranges" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Source IPs and CIDRs treated as trusted by the baseline WAF rules - typically
    corporate egress and VPN ranges.

    Required by `block_admin_from_untrusted`: that rule blocks admin paths for
    every source NOT in this list, so an empty list would lock out all
    administrative access including your own. Selecting a rule that depends on
    this while it is empty fails the plan.
  EOT

  validation {
    condition = alltrue([
      for range in var.waf_trusted_ip_ranges :
      can(cidrnetmask(range)) || can(regex("^[0-9a-fA-F:.]+$", range))
    ])
    error_message = "Each waf_trusted_ip_ranges entry must be an IPv4/IPv6 address or a CIDR range (e.g. 203.0.113.0/24)."
  }
}

variable "waf_admin_paths" {
  type        = list(string)
  default     = ["/admin", "/wp-login.php", "/wp-admin"]
  description = <<-EOT
    URI path fragments considered administrative by `block_admin_from_untrusted`
    and `log_trusted_admin_access`. Matched with `contains`, so "/admin" also
    matches "/admin/users".
  EOT

  validation {
    condition     = alltrue([for path in var.waf_admin_paths : startswith(path, "/")])
    error_message = "Each waf_admin_paths entry must start with \"/\"."
  }

  validation {
    condition     = alltrue([for path in var.waf_admin_paths : !strcontains(path, "\"")])
    error_message = "waf_admin_paths entries must not contain double quotes - they are interpolated into a Cloudflare expression."
  }
}

variable "waf_blocked_countries" {
  type        = list(string)
  default     = []
  description = <<-EOT
    ISO 3166-1 alpha-2 country codes blocked by the `geoblock_countries` baseline
    rule. Selecting that rule while this is empty fails the plan, because
    `ip.geoip.country in {}` is not a valid Cloudflare expression.
  EOT

  validation {
    condition     = alltrue([for code in var.waf_blocked_countries : can(regex("^[A-Z]{2}$", code))])
    error_message = "Each waf_blocked_countries entry must be an uppercase ISO 3166-1 alpha-2 code (e.g. \"CN\")."
  }
}

variable "waf_ip_blocklist_name" {
  type        = string
  default     = null
  description = <<-EOT
    Name of an account-scoped Cloudflare IP list that the `block_listed_ips`
    baseline rule blocks on. Selecting that rule while this is null fails the
    plan.

    THE LIST IS NOT CREATED HERE. It belongs to the `lists` layer, which applies
    before this one, and this is the name it was given in
    accounts/<account>/lists.tfvars. The two have to agree by hand: a rule
    referring to a list that does not exist is rejected by Cloudflare at apply
    time, and renaming the list without changing this leaves a rule that is
    valid, enabled and matches nothing.

    Why a list rather than a hardcoded set of addresses: the contents are
    operational rather than architectural. An address added during an incident
    takes effect the moment it is written to the list, with no Terraform run and
    no pull request, and it survives every later apply of this layer.
  EOT

  validation {
    condition     = var.waf_ip_blocklist_name == null || can(regex("^[a-z0-9_]{1,50}$", coalesce(var.waf_ip_blocklist_name, "x")))
    error_message = "waf_ip_blocklist_name must be 1-50 characters of lowercase letters, numbers and underscores - the same constraint Cloudflare puts on the list's name, because the rule refers to it as $name."
  }
}

# Managed ruleset parameters. These tune the baseline managed rulesets in
# locals.waf.tf for the whole account - a single zone that needs something
# different should name the ruleset directly in waf_policies[*].managed_rulesets.
variable "managed_rules_min_tier" {
  type        = string
  default     = "pro"
  description = <<-EOT
    Lowest rate plan allowed to carry `baseline_managed_rulesets` or
    `managed_rulesets`. A policy that asks for managed rules on a zone below this
    fails the plan.

    Pro, because that is Cloudflare's published floor for both the Cloudflare
    Managed Ruleset and the OWASP Core Ruleset. Free zones get the Cloudflare
    Free Managed Ruleset instead, which is not in the catalogue - a free zone
    already has it applied by Cloudflare.
  EOT

  validation {
    condition = contains([
      "free", "lite", "pro", "pro_plus", "business", "enterprise",
      "partners_free", "partners_pro", "partners_business",
      "partners_enterprise", "partners_ent",
    ], var.managed_rules_min_tier)
    error_message = "managed_rules_min_tier must be a valid Cloudflare rate plan ID."
  }
}

variable "waf_managed_rules_action" {
  type        = string
  default     = null
  description = <<-EOT
    Action forced on every rule in the `cloudflare_managed` baseline ruleset.
    Null - the default - leaves each rule on the action Cloudflare ships it with,
    which is the intended way to run the ruleset.

    Set it to "log" to roll the ruleset out in monitoring mode: the rules are
    evaluated and every match is recorded in Security Events, but nothing is
    blocked. That is the safe first deployment on a zone with real traffic,
    because a managed ruleset turned straight on will block some legitimate
    requests, and the log tells you which before customers do.
  EOT

  validation {
    condition = var.waf_managed_rules_action == null || contains(
      ["block", "challenge", "managed_challenge", "js_challenge", "log"],
      coalesce(var.waf_managed_rules_action, "log"),
    )
    error_message = "waf_managed_rules_action must be one of: block, challenge, managed_challenge, js_challenge, log - or null to leave Cloudflare's per-rule defaults alone."
  }
}

variable "waf_owasp_paranoia_level" {
  type        = number
  default     = 1
  description = <<-EOT
    Highest OWASP paranoia level left enabled on the `owasp_core` baseline
    ruleset. Levels above this are switched off by category tag, which also
    covers rules Cloudflare adds to those tags later.

    PL1 is Cloudflare's default and is the only level that can be considered
    safe for general traffic. Each level above it trades false negatives for
    false positives, steeply: PL3 and PL4 exist for applications with a narrow,
    well-understood request shape, and will block ordinary requests on anything
    else. Raise this only alongside waf_owasp_score_threshold, and only after
    running the result in log mode.
  EOT

  validation {
    condition     = contains([1, 2, 3, 4], var.waf_owasp_paranoia_level)
    error_message = "waf_owasp_paranoia_level must be 1, 2, 3 or 4."
  }
}

variable "waf_owasp_score_threshold" {
  type        = number
  default     = 40
  description = <<-EOT
    Anomaly score at which the OWASP Core Ruleset acts. Each matching OWASP rule
    adds its score to a running total, and the last rule in the ruleset fires
    once the total reaches this number.

    Cloudflare's published sensitivities: 60 = low, 40 = medium (their default),
    25 = high. A LOWER threshold acts on more traffic, so 25 is the aggressive
    setting and 60 the permissive one - which is the opposite of how the number
    reads.
  EOT

  validation {
    condition     = var.waf_owasp_score_threshold >= 1 && var.waf_owasp_score_threshold <= 100
    error_message = "waf_owasp_score_threshold must be between 1 and 100. Cloudflare's own sensitivities are 60 (low), 40 (medium) and 25 (high)."
  }
}

variable "waf_owasp_action" {
  type        = string
  default     = null
  description = <<-EOT
    Action taken when the OWASP anomaly score crosses waf_owasp_score_threshold.
    Null leaves Cloudflare's default for that rule.

    Worth setting to "log" for a first deployment. OWASP scoring is cumulative
    across unrelated rules, so the traffic that trips the threshold is harder to
    predict from the configuration than a single managed rule is.
  EOT

  validation {
    condition = var.waf_owasp_action == null || contains(
      ["block", "challenge", "managed_challenge", "js_challenge", "log"],
      coalesce(var.waf_owasp_action, "log"),
    )
    error_message = "waf_owasp_action must be one of: block, challenge, managed_challenge, js_challenge, log - or null to leave Cloudflare's default alone."
  }
}
