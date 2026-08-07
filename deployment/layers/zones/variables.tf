# Layer zones - inputs.
#
# This layer owns zone identity: the zone itself, its baseline settings, and its
# DNS records. It runs first, and nothing else may destroy a zone.
#
# Two config files feed it:
#   accounts/<account>/zones.tfvars - the zone inventory, shared with every layer
#   accounts/<account>/dns.tfvars   - zone configuration, consumed only here
#
# The inventory is deliberately separate and minimal. Later layers need to know
# that key "primary" means "example.com" so they can resolve it to a zone ID, but
# they have no business seeing DNS records. Keeping identity in its own file means
# the same file can be passed to every layer without each one having to declare
# the full zone schema.
variable "cloudflare_account_id" {
  type        = string
  description = <<-EOT
    Cloudflare Account ID this layer run targets. Supplied from
    accounts/<account>/account.tfvars, or overridden with
    TF_VAR_cloudflare_account_id.
  EOT

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: the logical key => domain name mapping for this account.
    Shared verbatim with layers waf and load_balancing, which resolve the
    key to a zone ID.

    The key is permanent identity. Renaming it destroys and recreates the zone,
    which takes every DNS record with it.

    - `domain_name` - The apex domain (e.g. example.com).
    - `zone_tier`   - (Optional) The zone's Cloudflare rate plan. Defaults to
                      var.default_zone_tier.

    zone_tier lives in the inventory rather than in dns.tfvars because the waf
    layer needs it too: bot traffic rules are plan-gated, and that layer never
    sees zone configuration. Every layer that consumes this file accepts the
    attribute, so adding it here does not break the others.
  EOT
  type = map(object({
    domain_name = string
    zone_tier   = optional(string)
  }))

  validation {
    condition     = alltrue([for key in keys(var.zones) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "zones keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
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

  validation {
    condition     = length(distinct([for z in var.zones : lower(z.domain_name)])) == length(var.zones)
    error_message = "Each zones entry must have a distinct domain_name; Cloudflare allows one zone per domain per account."
  }
}

variable "zone_config" {
  description = <<-EOT
    Per-zone configuration, keyed by the same key as `var.zones`. A zone with no
    entry here gets the platform defaults and no DNS records.

    - `zone_type`           - (Optional) full, partial, secondary or internal. Defaults to full.
    - `paused`              - (Optional) Pause Cloudflare proxying for the whole zone.
    - `ssl_mode`            - (Optional) Edge TLS (encryption) mode: off, flexible, full or
                              strict. Defaults to var.default_ssl_mode.
    - `min_tls_version`     - (Optional) 1.0, 1.1, 1.2 or 1.3. Defaults to
                              var.default_min_tls_version.
    - `tls_1_3`             - (Optional) on, off or zrt. Defaults to var.default_tls_1_3.
    - `always_use_https`    - (Optional) on or off. Defaults to var.default_always_use_https.
    - `zone_settings`       - (Optional) Extra string-valued setting_id => value pairs, merged
                              over var.default_zone_settings and the module's secure baseline.
    - `bot_management`      - (Optional) Zone-level bot posture. REPLACES
                              var.default_bot_management wholesale rather than merging with
                              it, so a zone that sets this must state its full posture. Unset
                              on both means no bot management resource is created and the
                              zone's current settings are left alone. Per-category
                              Search/Agent/Training rules are not here - they are the waf
                              layer's `bot_traffic`, because only one ruleset may own the
                              http_request_firewall_custom phase per zone.
    - `manage_subscription` - (Optional) Let Terraform set this zone's rate plan. Defaults to
                              var.manage_zone_subscriptions. THIS CHANGES BILLING - see that
                              variable.
    - `dns_records`         - (Optional) Records for the zone. Names may be "@", relative or
                              fully-qualified; the module qualifies them against the zone's
                              domain.
  EOT
  type = map(object({
    zone_type           = optional(string)
    paused              = optional(bool)
    ssl_mode            = optional(string)
    min_tls_version     = optional(string)
    tls_1_3             = optional(string)
    always_use_https    = optional(string)
    manage_subscription = optional(bool)
    zone_settings       = optional(map(string), {})
    bot_management = optional(object({
      fight_mode                      = optional(bool)
      sbfm_definitely_automated       = optional(string)
      sbfm_verified_bots              = optional(string)
      sbfm_static_resource_protection = optional(bool)
      optimize_wordpress              = optional(bool)
      sbfm_likely_automated           = optional(string)
      enable_js                       = optional(bool)
      auto_update_model               = optional(bool)
      suppress_session_score          = optional(bool)
      ai_bots_protection              = optional(string)
      crawler_protection              = optional(string)
      content_bots_protection         = optional(string)
      bm_cookie_enabled               = optional(bool)
      is_robots_txt_managed           = optional(bool)
      cf_robots_variant               = optional(string)
    }))
    dns_records = optional(list(object({
      name     = string
      type     = string
      content  = string
      ttl      = optional(number, 1)
      proxied  = optional(bool, false)
      priority = optional(number)
      comment  = optional(string)
      tags     = optional(set(string))
    })), [])
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Platform defaults (defaults.auto.tfvars in this directory)
# -----------------------------------------------------------------------------
variable "default_ssl_mode" {
  type        = string
  default     = "strict"
  description = "Edge TLS mode applied to any zone that does not set `ssl_mode` itself."

  validation {
    condition     = contains(["off", "flexible", "full", "strict"], var.default_ssl_mode)
    error_message = "default_ssl_mode must be one of: off, flexible, full, strict."
  }
}

variable "default_min_tls_version" {
  type        = string
  default     = "1.2"
  description = "Minimum TLS version applied to any zone that does not set `min_tls_version` itself."

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.default_min_tls_version)
    error_message = "default_min_tls_version must be one of: 1.0, 1.1, 1.2, 1.3."
  }
}

variable "default_tls_1_3" {
  type        = string
  default     = "on"
  description = <<-EOT
    TLS 1.3 support applied to any zone that does not set `tls_1_3` itself. One
    of: on, off, zrt.

    "zrt" adds 0-RTT resumption, which saves a round trip and makes early data
    replayable. Do not default it on for a fleet - turn it on per zone, once you
    know every endpoint reachable over early data is idempotent.
  EOT

  validation {
    condition     = contains(["on", "off", "zrt"], var.default_tls_1_3)
    error_message = "default_tls_1_3 must be one of: on, off, zrt."
  }
}

variable "default_always_use_https" {
  type        = string
  default     = "on"
  description = "Whether plaintext HTTP is redirected to HTTPS at the edge, for any zone that does not set `always_use_https` itself. One of: on, off."

  validation {
    condition     = contains(["on", "off"], var.default_always_use_https)
    error_message = "default_always_use_https must be one of: on, off."
  }
}

variable "default_zone_settings" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Zone settings applied to every zone in this account, merged under each zone's
    own `zone_settings`. The zone_base module applies a secure baseline
    (automatic_https_rewrites, opportunistic_encryption, browser_check, http3)
    underneath both, and the dedicated ssl_mode / min_tls_version / tls_1_3 /
    always_use_https variables on top of both, so this is for fleet-wide
    additions rather than for overriding TLS posture.
  EOT
}

# -----------------------------------------------------------------------------
# Zone tier and bot traffic
# -----------------------------------------------------------------------------
variable "default_zone_tier" {
  type        = string
  default     = "free"
  description = <<-EOT
    Rate plan assumed for any zone whose inventory entry does not set
    `zone_tier`. Drives feature gating in the zone_rules module: a bot
    management field the tier cannot support fails the plan with a message that
    names it, rather than failing at apply with a Cloudflare error that does not.
  EOT

  validation {
    condition = contains([
      "free", "lite", "pro", "pro_plus", "business", "enterprise",
      "partners_free", "partners_pro", "partners_business",
      "partners_enterprise", "partners_ent",
    ], var.default_zone_tier)
    error_message = "default_zone_tier must be one of: free, lite, pro, pro_plus, business, enterprise, partners_free, partners_pro, partners_business, partners_enterprise, partners_ent."
  }
}

variable "manage_zone_subscriptions" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether Terraform owns each zone's rate plan, for zones that do not override
    it with `manage_subscription`.

    OFF BY DEFAULT, AND THAT IS DELIBERATE. Turning it on means `terraform
    apply` moves every zone onto its `zone_tier`, so a typo in the inventory
    becomes a billing event, and a downgrade strips features - WAF rule
    allowances, Bot Management, rate limiting - from a live production zone in
    the same apply.

    It also widens this layer's API token from Zone/DNS/Zone Settings to include
    Billing Read and Billing Write. Prefer running that as a separate, deliberate
    change with its own token rather than leaving it enabled on the pipeline
    token used for routine DNS work.

    With this off, `zone_tier` still gates features - it just describes the plan
    each zone is already on.
  EOT
}

variable "default_subscription_frequency" {
  type        = string
  default     = "monthly"
  description = "Billing frequency used when a subscription is managed. One of: weekly, monthly, quarterly, yearly. Ignored entirely when manage_subscription is false."

  validation {
    condition     = contains(["weekly", "monthly", "quarterly", "yearly"], var.default_subscription_frequency)
    error_message = "default_subscription_frequency must be one of: weekly, monthly, quarterly, yearly."
  }
}

variable "default_bot_management" {
  type = object({
    fight_mode                      = optional(bool)
    sbfm_definitely_automated       = optional(string)
    sbfm_verified_bots              = optional(string)
    sbfm_static_resource_protection = optional(bool)
    optimize_wordpress              = optional(bool)
    sbfm_likely_automated           = optional(string)
    enable_js                       = optional(bool)
    auto_update_model               = optional(bool)
    suppress_session_score          = optional(bool)
    ai_bots_protection              = optional(string)
    crawler_protection              = optional(string)
    content_bots_protection         = optional(string)
    bm_cookie_enabled               = optional(bool)
    is_robots_txt_managed           = optional(bool)
    cf_robots_variant               = optional(string)
  })
  default     = null
  description = <<-EOT
    Bot posture applied to every zone that does not set `bot_management` itself.
    Null - the default - means this layer creates no bot management resource and
    leaves whatever is on each zone alone.

    A fleet default here is only safe if every zone in the account is on a tier
    that supports the fields it sets, because the gating is per zone. Setting
    sbfm_* fleet-wide across a mix of Free and Pro zones fails the plan on the
    Free ones, which is the intended behaviour but is worth knowing before you
    set it.

    See ../../../modules/zone_rules/variables.tf for the per-field plan
    requirements.
  EOT
}
