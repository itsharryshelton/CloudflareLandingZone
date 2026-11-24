# Adopting the client configuration that already exists.
#
# THE DEFAULT PROFILE
# Every Zero Trust account has one, created with the account and serving every
# device that no custom profile matches. Applied without an import, Terraform
# would "create" it - which at Cloudflare means overwriting the live profile
# from this configuration alone. So whenever device_default_profile is set,
# the block below adopts it first. The import id is the account ID; the block
# is a no-op once the profile is in state, and is resolved at plan time, so the
# saved plan the pipeline applies already carries it.
#
# Read the first plan after adopting it line by line. An attribute
# devices.tfvars leaves unset is not left alone: provider 5.23 sends its own
# default (allowed_to_leave = true, captive_portal = 180 and so on), and the
# plan shows each as a change from what the dashboard holds today.
import {
  for_each = var.device_default_profile == null ? {} : { default = var.cloudflare_account_id }

  to = module.device_profiles.cloudflare_zero_trust_device_default_profile.this[0]
  id = each.value
}

# DEVICE SETTINGS
# Provider 5.23 cannot import cloudflare_zero_trust_device_settings ("Resource
# Import Not Implemented"), so there is no block for it. The first apply writes
# it from devices.tfvars alone, which is why every switch in device_settings is
# required. Copy the current values from the dashboard before setting it.
#
# CUSTOM PROFILES
# A profile made in the dashboard is not matched by name: applied alongside it,
# this layer creates a second profile, and whichever has the lower precedence
# wins for the devices both match. List the existing ones first:
#
#   curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
#     "https://api.cloudflare.com/client/v4/accounts/<account_id>/devices/policies" \
#     | jq -r '.result[] | [.policy_id, .precedence, .name, .match] | @tsv'
#
# For each that matches a profile in devices.tfvars, uncomment the block below
# and map the logical key to its EXISTING policy ID. The import id is
# "<account_id>/<policy_id>". Once everything is in state this map can be
# emptied again.
#
# import {
#   for_each = {
#     # <logical key in device_custom_profiles> = "<existing policy id>"
#     # engineering = "00000000-0000-0000-0000-000000000000"
#   }
#
#   to = module.device_profiles.cloudflare_zero_trust_device_custom_profile.this[each.key]
#   id = "${var.cloudflare_account_id}/${each.value}"
# }
#
# LOCAL DOMAIN FALLBACK
# Not imported: a managed list is written whole on every apply, so there is
# nothing in the existing one to preserve except what devices.tfvars declares
# (with baseline_fallback_domains prepended).
#
# STOPPING MANAGEMENT
# Provider 5.23 cannot delete the default profile or a fallback list: setting
# either back to null drops it from state and leaves its last configuration at
# Cloudflare. device_settings is different - the provider does delete it, and
# what Cloudflare resets it to is not documented. To stop managing it without
# that, add a `removed` block for its address with
# `lifecycle { destroy = false }` in the same change.
