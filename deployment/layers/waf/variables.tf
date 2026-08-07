# Layer: waf - inputs.
#
# Custom firewall rules and rate limiting. Runs after zones and holds its own
# state, so an apply here can never propose destroying a zone.
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
    - `custom_block_rules`      - (Optional) Tenant-specific firewall rules, appended after
                                  the baseline rules so they evaluate later.
    - `rate_limiting_rules`     - (Optional) Tenant-specific rate limits, appended after the
                                  baseline rate limits.
    - `custom_ruleset_name`     - (Optional) Dashboard display name for the custom ruleset.
    - `rate_limit_ruleset_name` - (Optional) Dashboard display name for the rate limit ruleset.

    Baseline rules are parameterised by `waf_trusted_ip_ranges`, `waf_admin_paths`
    and `waf_blocked_countries` rather than hardcoded, so the catalogue serves
    every customer.
  EOT
  type = map(object({
    zone_key                = string
    baseline_custom_rules   = optional(list(string), [])
    baseline_rate_limits    = optional(list(string), [])
    custom_ruleset_name     = optional(string)
    rate_limit_ruleset_name = optional(string)
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
