# Module zone_rules - inputs.
#
# Zone tier (rate plan) and bot traffic posture for a single zone.

variable "zone_id" {
  type        = string
  description = "Target Cloudflare Zone ID (typically module.zone_base.zone_id)."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hexadecimal Cloudflare zone identifier."
  }
}

# Zone tier
variable "zone_tier" {
  type        = string
  default     = "free"
  description = <<-EOT
    The zone's Cloudflare rate plan. Two jobs:

      1. Feature gating. Bot Management fields are plan-locked, and Cloudflare
         rejects an unsupported field at apply time with an error that does not
         name the field. The preconditions in main.tf fail the plan instead,
         naming what is unsupported and on which tier.
      2. Optionally, the plan itself - see `manage_subscription`.

    Accepted values are the rate plan IDs the Cloudflare API accepts:
      free, lite, pro, pro_plus, business, enterprise,
      partners_free, partners_pro, partners_business, partners_enterprise,
      partners_ent
  EOT

  validation {
    condition = contains([
      "free", "lite", "pro", "pro_plus", "business", "enterprise",
      "partners_free", "partners_pro", "partners_business",
      "partners_enterprise", "partners_ent",
    ], var.zone_tier)
    error_message = "zone_tier must be one of: free, lite, pro, pro_plus, business, enterprise, partners_free, partners_pro, partners_business, partners_enterprise, partners_ent."
  }
}

variable "manage_subscription" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether Terraform owns the zone's rate plan via cloudflare_zone_subscription.

    OFF BY DEFAULT, AND THAT IS DELIBERATE. When true, `terraform apply` will
    move the zone onto `zone_tier` - which means an apply can upgrade or
    downgrade a paid Cloudflare plan and change what the account is billed. A
    typo in zone_tier becomes a billing event, and a downgrade silently strips
    features (WAF rule allowances, Bot Management) from a live zone.

    API Perms needed if adjusting plans: Billing Read and Billing Write on top of Zone Settings.

    With this false, `zone_tier` is still honoured for feature gating - it just
    describes the plan the zone is already on rather than setting it.
  EOT
}

variable "subscription_frequency" {
  type        = string
  default     = "monthly"
  description = <<-EOT
    Billing frequency for the subscription, used only when
    `manage_subscription` is true. One of: weekly, monthly, quarterly, yearly.
    Not every plan offers every frequency; Cloudflare rejects the combination
    at apply time if it does not.
  EOT

  validation {
    condition     = contains(["weekly", "monthly", "quarterly", "yearly"], var.subscription_frequency)
    error_message = "subscription_frequency must be one of: weekly, monthly, quarterly, yearly."
  }
}

# Bot traffic
variable "bot_management" {
  type = object({
    # Free / Lite
    fight_mode = optional(bool)

    # Pro and above (Super Bot Fight Mode)
    sbfm_definitely_automated       = optional(string)
    sbfm_verified_bots              = optional(string)
    sbfm_static_resource_protection = optional(bool)
    optimize_wordpress              = optional(bool)

    # Business and above
    sbfm_likely_automated = optional(string)

    # Enterprise with a Bot Management subscription
    enable_js              = optional(bool)
    auto_update_model      = optional(bool)
    suppress_session_score = optional(bool)

    # AI and crawler controls.
    ai_bots_protection      = optional(string)
    crawler_protection      = optional(string)
    content_bots_protection = optional(string)
    bm_cookie_enabled       = optional(bool)
    is_robots_txt_managed   = optional(bool)
    cf_robots_variant       = optional(string)
  })
  default     = null
  description = <<-EOT
    Zone-level bot posture, applied as a single cloudflare_bot_management
    resource. Leave null (the default) and no bot management resource is
    created at all, which leaves whatever is currently set on the zone alone.

    Plan gating is enforced by preconditions in main.tf against `zone_tier`.

      - `fight_mode`                     - Bot Fight Mode. Free/Lite only, and mutually
                                           exclusive with every sbfm_* field: on Pro and
                                           above the equivalent is Super Bot Fight Mode.
      - `sbfm_definitely_automated`      - allow | block | managed_challenge. Pro+.
      - `sbfm_verified_bots`             - allow | block. Pro+. This is the blunt
                                           instrument version of `bot_traffic` in the waf
                                           module: it treats every verified bot the same,
                                           with no per-category split.
      - `sbfm_static_resource_protection`- Extend SBFM actions to static assets. Pro+.
      - `optimize_wordpress`             - Skip SBFM for known-good WordPress traffic. Pro+.
      - `sbfm_likely_automated`          - allow | block | managed_challenge. Business+.
      - `enable_js`                      - Inject the bot detection JS. Enterprise + Bot Management.
      - `auto_update_model`              - Track Cloudflare's latest ML model. Enterprise + Bot Management.
      - `suppress_session_score`         - Score on the request only, not the session.
                                           Enterprise + Bot Management.
      - `ai_bots_protection`             - block | disabled | only_on_ad_pages. Blocks AI
                                           crawlers including ones that are NOT verified,
                                           which per-category WAF rules cannot reach.
      - `crawler_protection`             - enabled | disabled.
      - `content_bots_protection`        - block | disabled.
      - `bm_cookie_enabled`              - Bot management cookie. Defaults to true at Cloudflare.
      - `is_robots_txt_managed`          - Let Cloudflare manage the zone's robots.txt.
      - `cf_robots_variant`              - off | policy_only. Which managed robots.txt to serve.

    Note that this resource has no delete operation that returns the zone to a
    pristine state; removing the block drops it from Terraform state and leaves
    the last applied values live on the zone, exactly as zone settings do.
  EOT

  validation {
    condition = (
      var.bot_management == null ||
      alltrue([
        for value in [
          try(var.bot_management.sbfm_definitely_automated, null),
          try(var.bot_management.sbfm_likely_automated, null),
        ] : value == null || contains(["allow", "block", "managed_challenge"], coalesce(value, "allow"))
      ])
    )
    error_message = "bot_management.sbfm_definitely_automated and sbfm_likely_automated must be one of: allow, block, managed_challenge."
  }

  validation {
    condition = (
      var.bot_management == null ||
      try(var.bot_management.sbfm_verified_bots, null) == null ||
      contains(["allow", "block"], coalesce(try(var.bot_management.sbfm_verified_bots, null), "allow"))
    )
    error_message = "bot_management.sbfm_verified_bots must be one of: allow, block."
  }

  validation {
    condition = (
      var.bot_management == null ||
      try(var.bot_management.ai_bots_protection, null) == null ||
      contains(["block", "disabled", "only_on_ad_pages"], coalesce(try(var.bot_management.ai_bots_protection, null), "disabled"))
    )
    error_message = "bot_management.ai_bots_protection must be one of: block, disabled, only_on_ad_pages."
  }

  validation {
    condition = (
      var.bot_management == null ||
      try(var.bot_management.crawler_protection, null) == null ||
      contains(["enabled", "disabled"], coalesce(try(var.bot_management.crawler_protection, null), "disabled"))
    )
    error_message = "bot_management.crawler_protection must be one of: enabled, disabled."
  }

  validation {
    condition = (
      var.bot_management == null ||
      try(var.bot_management.content_bots_protection, null) == null ||
      contains(["block", "disabled"], coalesce(try(var.bot_management.content_bots_protection, null), "disabled"))
    )
    error_message = "bot_management.content_bots_protection must be one of: block, disabled."
  }

  validation {
    condition = (
      var.bot_management == null ||
      try(var.bot_management.cf_robots_variant, null) == null ||
      contains(["off", "policy_only"], coalesce(try(var.bot_management.cf_robots_variant, null), "off"))
    )
    error_message = "bot_management.cf_robots_variant must be one of: off, policy_only."
  }
}
