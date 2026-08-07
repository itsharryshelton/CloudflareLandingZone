# Tier normalisation and plan gating.

locals {
  # Rate plan ID => capability rank. The partners_* plans are reseller
  # equivalents and gate identically to the plan they mirror, so they collapse
  # onto the same rank rather than getting their own branch in every condition
  # below. `lite` is legacy and sits above free without unlocking Super Bot
  # Fight Mode, hence its own rank.
  tier_rank = {
    free                = 0
    partners_free       = 0
    lite                = 1
    pro                 = 2
    pro_plus            = 2
    partners_pro        = 2
    business            = 3
    partners_business   = 3
    enterprise          = 4
    partners_enterprise = 4
    partners_ent        = 4
  }

  rank = local.tier_rank[var.zone_tier]

  # Ranks named, so the conditions below read as the plan names an operator recognises rather than numbers
  tier_is_free_or_lite = local.rank <= 1
  tier_is_pro_plus     = local.rank >= 2
  tier_is_business     = local.rank >= 3
  tier_is_enterprise   = local.rank >= 4

  # A convenience alias so every lookup below can use try() against a possibly null object without repeating var.bot_management
  bm = var.bot_management

  bm_fight_mode                      = try(local.bm.fight_mode, null)
  bm_sbfm_definitely_automated       = try(local.bm.sbfm_definitely_automated, null)
  bm_sbfm_likely_automated           = try(local.bm.sbfm_likely_automated, null)
  bm_sbfm_verified_bots              = try(local.bm.sbfm_verified_bots, null)
  bm_sbfm_static_resource_protection = try(local.bm.sbfm_static_resource_protection, null)
  bm_optimize_wordpress              = try(local.bm.optimize_wordpress, null)
  bm_enable_js                       = try(local.bm.enable_js, null)
  bm_auto_update_model               = try(local.bm.auto_update_model, null)
  bm_suppress_session_score          = try(local.bm.suppress_session_score, null)
  bm_ai_bots_protection              = try(local.bm.ai_bots_protection, null)
  bm_crawler_protection              = try(local.bm.crawler_protection, null)
  bm_content_bots_protection         = try(local.bm.content_bots_protection, null)
  bm_cookie_enabled                  = try(local.bm.bm_cookie_enabled, null)
  bm_is_robots_txt_managed           = try(local.bm.is_robots_txt_managed, null)
  bm_cf_robots_variant               = try(local.bm.cf_robots_variant, null)

  # Field => (is it set, is this tier allowed to set it, what it needs).
  # Cloudflare rejects an out-of-plan bot management field at apply time with a generic API error that does not name the field, after some of the other fields in the same PUT may already have landed. Failing the plan instead costs nothing and says which field and which tier.
  #
  # ai_bots_protection, crawler_protection, content_bots_protection,
  # bm_cookie_enabled, is_robots_txt_managed and cf_robots_variant are
  # deliberately absent: Cloudflare documents no plan floor for them, and a
  # guess here would block a legitimate configuration.
  bot_gates = {
    fight_mode = {
      set      = local.bm_fight_mode != null
      allowed  = local.tier_is_free_or_lite
      requires = "Free or Lite - on Pro and above the equivalent is Super Bot Fight Mode, so use the sbfm_* fields"
    }
    sbfm_definitely_automated = {
      set      = local.bm_sbfm_definitely_automated != null
      allowed  = local.tier_is_pro_plus
      requires = "Pro or above (Super Bot Fight Mode)"
    }
    sbfm_verified_bots = {
      set      = local.bm_sbfm_verified_bots != null
      allowed  = local.tier_is_pro_plus
      requires = "Pro or above (Super Bot Fight Mode)"
    }
    sbfm_static_resource_protection = {
      set      = local.bm_sbfm_static_resource_protection != null
      allowed  = local.tier_is_pro_plus
      requires = "Pro or above (Super Bot Fight Mode)"
    }
    optimize_wordpress = {
      set      = local.bm_optimize_wordpress != null
      allowed  = local.tier_is_pro_plus
      requires = "Pro or above (Super Bot Fight Mode)"
    }
    sbfm_likely_automated = {
      set      = local.bm_sbfm_likely_automated != null
      allowed  = local.tier_is_business
      requires = "Business or above"
    }
    enable_js = {
      set      = local.bm_enable_js != null
      allowed  = local.tier_is_enterprise
      requires = "Enterprise with a Bot Management subscription"
    }
    auto_update_model = {
      set      = local.bm_auto_update_model != null
      allowed  = local.tier_is_enterprise
      requires = "Enterprise with a Bot Management subscription"
    }
    suppress_session_score = {
      set      = local.bm_suppress_session_score != null
      allowed  = local.tier_is_enterprise
      requires = "Enterprise with a Bot Management subscription"
    }
  }

  unsupported_bot_features = [
    for field, gate in local.bot_gates :
    "${field} requires ${gate.requires}"
    if gate.set && !gate.allowed
  ]

  # Bot Fight Mode and Super Bot Fight Mode are the same control at two plan
  # levels, not two controls. Cloudflare accepts the PUT and then behaves in a
  # way that matches neither intent.
  sbfm_fields_set = compact([
    local.bm_sbfm_definitely_automated == null ? "" : "sbfm_definitely_automated",
    local.bm_sbfm_likely_automated == null ? "" : "sbfm_likely_automated",
    local.bm_sbfm_verified_bots == null ? "" : "sbfm_verified_bots",
    local.bm_sbfm_static_resource_protection == null ? "" : "sbfm_static_resource_protection",
  ])

  fight_mode_conflicts = (
    coalesce(local.bm_fight_mode, false) && length(local.sbfm_fields_set) > 0
  )
}
