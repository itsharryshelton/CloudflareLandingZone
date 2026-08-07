output "zone_tier" {
  value       = var.zone_tier
  description = "The rate plan this zone is gated against, echoed back for pipeline reporting."
}

output "subscription_id" {
  value       = length(cloudflare_zone_subscription.this) > 0 ? cloudflare_zone_subscription.this[0].id : null
  description = "Subscription ID when manage_subscription is true, otherwise null."
}

output "subscription_state" {
  value       = length(cloudflare_zone_subscription.this) > 0 ? cloudflare_zone_subscription.this[0].state : null
  description = "Subscription state as reported by Cloudflare (Trial, Provisioned, Paid, AwaitingPayment, Cancelled, Failed, Expired), or null when the subscription is not managed here. A plan change that lands as AwaitingPayment has not taken effect."
}

output "bot_management_managed" {
  value       = var.bot_management != null
  description = "Whether this module owns the zone's bot management configuration."
}

output "using_latest_bot_model" {
  value       = length(cloudflare_bot_management.this) > 0 ? cloudflare_bot_management.this[0].using_latest_model : null
  description = "Whether the zone runs Cloudflare's latest bot detection model. Null when bot management is not managed here."
}

output "tier_capabilities" {
  description = "What the configured tier unlocks. Exposed so a caller can gate its own configuration on the same ranking this module uses, rather than re-deriving it."
  value = {
    rank                  = local.rank
    super_bot_fight_mode  = local.tier_is_pro_plus
    sbfm_likely_automated = local.tier_is_business
    bot_management_fields = local.tier_is_enterprise
  }
}
