# Device posture: the service provider connections Cloudflare polls, and the
# checks an Access or Gateway policy can require a device to have passed.
#
# Input mapping and reference resolution live in locals.tf. The preconditions
# below need more than one input, so they cannot be variable validations.

# Connections to a third-party MDM or EDR. Cloudflare tests the credential when
# the integration is created, so a wrong secret fails the apply, not the plan.
resource "cloudflare_zero_trust_device_posture_integration" "this" {
  for_each = local.integrations

  account_id = var.account_id
  name       = trimspace(each.value.name)
  type       = each.value.type
  interval   = each.value.interval
  config     = each.value.config
}

# The checks themselves. Access and Gateway reference a rule by ID, and neither
# can see this module's state, so renaming a rule - which replaces it - leaves
# every policy holding the old ID requiring a check that no longer exists.
resource "cloudflare_zero_trust_device_posture_rule" "this" {
  for_each = local.rules

  account_id  = var.account_id
  name        = trimspace(each.value.name)
  type        = each.value.type
  description = each.value.description
  schedule    = each.value.schedule
  expiration  = each.value.expiration
  input       = local.rule_inputs[each.key]
  match       = local.rule_matches[each.key]

  lifecycle {
    precondition {
      condition     = length(local.unknown_integration_names) == 0
      error_message = "integration_name does not match any entry in var.integrations: ${join("; ", local.unknown_integration_names)}. Declared integrations: ${join(", ", local.integration_keys)}. Use integration_id for an integration managed outside this module."
    }

    precondition {
      condition     = length(local.mismatched_integration_types) == 0
      error_message = "These rules read through an integration of a different type: ${join("; ", local.mismatched_integration_types)}. A rule only ever passes on the attributes its own provider sends, so an intune rule needs an intune integration, a crowdstrike_s2s rule a crowdstrike_s2s one, and so on."
    }
  }
}
