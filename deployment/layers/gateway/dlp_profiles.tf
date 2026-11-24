# Custom DLP profiles, one module instance per profile.
#
# Here for the same reason as the lists: the baseline DLP rule and any account
# policy name a profile by key, and the profile and the rule blocking on it
# land together. Cloudflare's predefined profiles are not created here - they
# exist on every account - and are still named by UUID.
#
# Downstream deployments pin an immutable tag instead of the placeholder:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//dlp_profile?ref=v1.0.0"
module "dlp_profile" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//dlp_profile"

  for_each   = var.gateway_dlp_profiles
  account_id = var.cloudflare_account_id

  name        = each.value.name
  description = each.value.description
  entries     = each.value.entries

  allowed_match_count  = each.value.allowed_match_count
  confidence_threshold = each.value.confidence_threshold
  ocr_enabled          = each.value.ocr_enabled
  ai_context_enabled   = each.value.ai_context_enabled
}
