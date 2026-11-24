# One custom Data Loss Prevention profile and its detection entries.
#
# The profile is what a Gateway HTTP policy names (`any(dlp.profiles[*] in
# {"<uuid>"})`); the entries are the patterns it is made of. They are separate
# resources because the provider deprecates the profile's inline `entries`
# block in favour of cloudflare_zero_trust_dlp_custom_entry - and with the
# inline block omitted, the profile resource leaves its entries alone, so the
# two never fight over them.
#
# Cloudflare's predefined profiles (Financial Information, Credentials and
# Secrets, ...) are not managed here. They exist on every account already, and
# no data source resolves one by name, so a policy that wants one names its UUID
# directly.
#
# A DLP profile only sees what Gateway decrypts. An application bypassed from
# inspection, or traffic while TLS decryption is off, is never scanned against
# it however the policy is written.
resource "cloudflare_zero_trust_dlp_custom_profile" "this" {
  account_id  = var.account_id
  name        = var.name
  description = var.description

  allowed_match_count  = var.allowed_match_count
  confidence_threshold = var.confidence_threshold
  ocr_enabled          = var.ocr_enabled
  ai_context_enabled   = var.ai_context_enabled

  lifecycle {
    precondition {
      condition     = length(local.duplicate_entry_names) == 0
      error_message = "Two entries share a name (compared lower-cased): ${join(", ", local.duplicate_entry_names)}. The name is the entry's key here and its label in every Gateway log line, so each must be unique within the profile."
    }

    precondition {
      condition     = length(local.uncompilable_patterns) == 0
      error_message = "These entry patterns do not compile: ${join("; ", local.uncompilable_patterns)}. Cloudflare's DLP engine has no lookaround and no backreferences, like Terraform's RE2, so a pattern that fails here is one the API would reject - after the profile had been created."
    }

    # The one DLP mistake that is worse than a pattern that never matches.
    precondition {
      condition     = length(local.empty_matching_patterns) == 0
      error_message = "These entry patterns match the empty string, and therefore every request body: ${join("; ", local.empty_matching_patterns)}. A Gateway block on this profile would block every inspected upload and form post on the estate. Anchor the pattern on something that has to be present - `[0-9]{16}` rather than `[0-9]*`."
    }

    precondition {
      condition     = local.enabled_entry_count > 0
      error_message = "Every entry in this profile is disabled, so it matches nothing while a policy blocking on it appears in the dashboard as a working control. Enable at least one entry, or stop referencing the profile."
    }
  }
}

resource "cloudflare_zero_trust_dlp_custom_entry" "this" {
  for_each = local.entries

  account_id  = var.account_id
  profile_id  = cloudflare_zero_trust_dlp_custom_profile.this.id
  name        = trimspace(each.value.name)
  description = each.value.description
  enabled     = each.value.enabled

  pattern = {
    regex      = each.value.regex
    validation = each.value.validation
  }
}
