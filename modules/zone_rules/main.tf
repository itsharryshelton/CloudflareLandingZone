# Zone tier
# BILLING. Creating this resource makes Terraform the owner of the zone's rate
# plan, so an apply can upgrade or downgrade a paid plan. It is created only
# when the caller explicitly opts in with manage_subscription = true; see the
# warning on that variable. Requires Billing Read and Billing Write on the API
# token, which the other layers in this repository deliberately do not need.
resource "cloudflare_zone_subscription" "this" {
  count = var.manage_subscription ? 1 : 0

  zone_id   = var.zone_id
  frequency = var.subscription_frequency

  rate_plan = {
    id = var.zone_tier
  }
}

# Bot traffic - zone-level bot posture. Per-category Search / Agent / Training rules are NOT
# here - see `bot_traffic` in ../waf/variables.tf.
# The two are complementary rather than alternatives. ai_bots_protection and
# crawler_protection below act on unverified crawlers, which a rule matching
# cf.verified_bot_category cannot see at all.
resource "cloudflare_bot_management" "this" {
  count = var.bot_management == null ? 0 : 1

  zone_id = var.zone_id

  fight_mode = local.bm_fight_mode

  sbfm_definitely_automated       = local.bm_sbfm_definitely_automated
  sbfm_likely_automated           = local.bm_sbfm_likely_automated
  sbfm_verified_bots              = local.bm_sbfm_verified_bots
  sbfm_static_resource_protection = local.bm_sbfm_static_resource_protection
  optimize_wordpress              = local.bm_optimize_wordpress

  enable_js              = local.bm_enable_js
  auto_update_model      = local.bm_auto_update_model
  suppress_session_score = local.bm_suppress_session_score

  ai_bots_protection      = local.bm_ai_bots_protection
  crawler_protection      = local.bm_crawler_protection
  content_bots_protection = local.bm_content_bots_protection
  bm_cookie_enabled       = local.bm_cookie_enabled
  is_robots_txt_managed   = local.bm_is_robots_txt_managed
  cf_robots_variant       = local.bm_cf_robots_variant

  lifecycle {
    precondition {
      condition     = length(local.unsupported_bot_features) == 0
      error_message = "bot_management sets fields the zone's tier does not support (zone_tier = \"${var.zone_tier}\"): ${join("; ", local.unsupported_bot_features)}. Either raise zone_tier to match the plan the zone is actually on, or drop those fields."
    }

    precondition {
      condition     = !local.fight_mode_conflicts
      error_message = "bot_management sets fight_mode = true alongside ${join(", ", local.sbfm_fields_set)}. Bot Fight Mode and Super Bot Fight Mode are the same control at two plan levels, not two controls - set one or the other, never both."
    }
  }
}
