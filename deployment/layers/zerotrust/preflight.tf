resource "terraform_data" "preflight" {
  input = {
    identity_providers  = length(var.identity_providers)
    access_groups       = length(var.access_groups)
    access_policies     = length(var.access_policies)
    access_applications = length(var.access_applications)
    service_tokens      = length(var.service_tokens)
  }

  lifecycle {
    # An account with no Zero Trust organization has no team name, and Terraform
    # cannot choose one. In practice organization_lookup.tf has already failed by
    # the time this is reached; the message is here for the case where the read
    # succeeded but returned nothing.
    precondition {
      condition     = local.effective_team_name != ""
      error_message = "Account ${var.cloudflare_account_id} has no Zero Trust team name, and none was configured. Terraform cannot create one - the provider updates the Zero Trust organization rather than creating it. Choose the team name once in the dashboard under Zero Trust, then Settings, then Custom Pages, or POST to /accounts/${var.cloudflare_account_id}/access/organizations with a name and an auth_domain of <team>.cloudflareaccess.com. Then set zero_trust_team_name in the account tree and re-run."
    }

    # A rename is invisible in the plan - one attribute changes - and total in
    # its effect. Every Access URL, every enrolled device, every bookmark.
    precondition {
      condition     = !local.team_name_conflict || var.allow_team_name_change
      error_message = "zero_trust_team_name is \"${local.configured_team_name}\" but account ${var.cloudflare_account_id} already uses \"${local.existing_team_name}\". Applying this renames the team domain to ${local.configured_team_name}.cloudflareaccess.com: every Access application URL changes, every enrolled WARP device has to be re-enrolled, and ${local.existing_team_name}.cloudflareaccess.com is released for anybody else to claim. Correct the typo, or set allow_team_name_change = true if the rename is deliberate."
    }

    precondition {
      condition     = length(local.unknown_group_keys) == 0
      error_message = "group_keys does not match any entry in var.access_groups: ${join("; ", local.unknown_group_keys)}. Valid keys: ${join(", ", sort(keys(var.access_groups)))}. Use group_ids for a group managed outside this layer."
    }

    precondition {
      condition     = length(local.unknown_service_token_keys) == 0
      error_message = "service_token_keys does not match any entry in var.service_tokens: ${join("; ", local.unknown_service_token_keys)}. Valid keys: ${join(", ", sort(keys(var.service_tokens)))}. Use service_token_ids for a token managed outside this layer."
    }

    precondition {
      condition     = length(local.unknown_identity_provider_keys) == 0
      error_message = "An identity provider key matches no entry in var.identity_providers: ${join("; ", local.unknown_identity_provider_keys)}. Valid keys: ${join(", ", sort(keys(var.identity_providers)))}. Use the matching *_id field for a provider managed outside this layer."
    }

    precondition {
      condition     = length(local.unknown_policy_keys) == 0
      error_message = "policy_keys does not match any entry in var.access_policies: ${join("; ", local.unknown_policy_keys)}. Valid keys: ${join(", ", sort(keys(var.access_policies)))}. Left unchecked, the application would be created protected by fewer policies than it was meant to have."
    }

    precondition {
      condition     = length(local.ambiguous_identity_provider_references) == 0
      error_message = "These rules set both identity_provider_key and identity_provider_id, or neither: ${join("; ", local.ambiguous_identity_provider_references)}. Give exactly one - the key for a provider in var.identity_providers, the ID for one managed elsewhere."
    }

    precondition {
      condition     = length(local.restricted_decisions_used) == 0
      error_message = "A restricted policy decision was requested: ${join("; ", local.restricted_decisions_used)}. Restricted decisions are ${join(", ", var.restricted_policy_decisions)}, set in layers/zerotrust/defaults.auto.tfvars. \"bypass\" removes authentication entirely from every application the policy is attached to, so allowing it is a deliberate change to that list on its own pull request - not an account tree edit."
    }

    precondition {
      condition     = length(local.disallowed_email_references) == 0
      error_message = "An Access rule admits an email address or domain outside the permitted domains: ${join("; ", local.disallowed_email_references)}. Permitted: ${join(", ", local.allowed_email_domains)}, set through allowed_email_domains. Only include rules are checked - excluding an outside address is not the problem."
    }

    # A provider created without its secret is accepted by Cloudflare and then
    # fails at the login page, for everybody, with an error from the identity
    # provider rather than from Cloudflare.
    precondition {
      condition     = length(local.identity_providers_missing_secret) == 0
      error_message = "These identity providers authenticate against an OAuth application but have no entry in var.identity_provider_secrets: ${join("; ", local.identity_providers_missing_secret)}. The secret is supplied by the pipeline as TF_VAR_identity_provider_secrets, keyed by the same key - never from a .tfvars file. See layers/zerotrust/variables.tf."
    }

    # A secret with no provider is a secret nobody rotates and nobody misses.
    precondition {
      condition     = length(local.orphaned_identity_provider_secrets) == 0
      error_message = "identity_provider_secrets holds entries for keys that are not in var.identity_providers: ${join(", ", local.orphaned_identity_provider_secrets)}. Either the provider was removed and the secret was not, or the key is misspelled and the provider it was meant for is about to be created without one. Revoke the secret at the identity provider and remove it from the environment."
    }
  }
}
