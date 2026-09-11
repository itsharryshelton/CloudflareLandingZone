resource "terraform_data" "preflight" {
  input = {
    device_posture_integrations = length(var.device_posture_integrations)
    device_posture_rules        = length(var.device_posture_rules)
  }

  lifecycle {
    precondition {
      condition     = length(local.unknown_integration_keys) == 0
      error_message = "integration_key does not match any entry in var.device_posture_integrations: ${join("; ", local.unknown_integration_keys)}. Valid keys: ${join(", ", sort(keys(var.device_posture_integrations)))}. Use integration_id for an integration managed outside this layer."
    }

    # Cloudflare accepts the integration and then fails its own connection test
    # at apply - after the plan was approved, with the provider's error rather
    # than ours.
    precondition {
      condition     = length(local.integrations_missing_config) == 0
      error_message = "These integrations are missing connection settings their type needs: ${join("; ", local.integrations_missing_config)}. See var.device_posture_integrations in layers/device_posture/variables.tf for what each provider takes."
    }

    precondition {
      condition     = length(local.integrations_missing_secret) == 0
      error_message = "These integrations have no credential in var.device_posture_integration_secrets: ${join("; ", local.integrations_missing_secret)}. The credential is supplied by the pipeline as TF_VAR_device_posture_integration_secrets, from the <account>-plan environment, keyed by the same key - never from a .tfvars file."
    }

    # A credential nobody's integration reads is one nobody rotates and nobody
    # misses when it leaks.
    precondition {
      condition     = length(local.orphaned_integration_secrets) == 0
      error_message = "device_posture_integration_secrets holds credentials no integration uses: ${join(", ", local.orphaned_integration_secrets)}. Either the integration was removed and its secret was not, the key is misspelled and the integration it was meant for is about to connect without one, or the field is not one its type reads. Revoke it at the provider and remove it from the environment."
    }

    precondition {
      condition     = length(local.inverted_firewall_checks) == 0
      error_message = "These firewall checks set input.enabled = false: ${join("; ", local.inverted_firewall_checks)}. That does not switch the check off - it makes it pass only on devices whose firewall is OFF, so every policy requiring it admits exactly the devices it was meant to stop. Set enabled = true, or remove the rule."
    }

    precondition {
      condition     = length(local.unsigned_binary_checks) == 0
      error_message = "These checks name a binary but no signing certificate thumbprint: ${join("; ", local.unsigned_binary_checks)}. Without one, any file at that path passes - an empty executable with the agent's name satisfies \"the agent is running\". Add input.thumbprint, or set require_signed_binary_checks = false in layers/device_posture/defaults.auto.tfvars on a pull request that says why."
    }

    # Cloudflare recommends at least twice the polling period. Any shorter and a
    # result lapses before the next one arrives, so a healthy device fails the
    # check for part of every cycle.
    precondition {
      condition     = length(local.short_expirations) == 0
      error_message = "These rules expire their result before it is refreshed twice: ${join("; ", local.short_expirations)}. Devices would fail intermittently for no reason of their own. Set expiration to at least twice the schedule or integration interval, or leave it unset to have one derived."
    }

    precondition {
      condition     = length(local.restricted_types_used) == 0
      error_message = "A restricted posture rule type was requested: ${join("; ", local.restricted_types_used)}. Restricted types are ${join(", ", var.restricted_posture_rule_types)}, set in layers/device_posture/defaults.auto.tfvars. The legacy tanium check is Access-only and Gateway cannot evaluate it; use a tanium_s2s integration instead."
    }
  }
}
