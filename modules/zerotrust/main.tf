# Zero Trust: the organisation every Access login happens under, the login
# methods it offers, the audiences it recognises, and the applications it
# protects.
#
# Rule mapping and reference resolution live in locals.tf. The preconditions
# below are the checks that need more than one input, so they cannot be
# variable validations.

# The team name, session lengths and dashboard lock for the whole account.
#
# The provider creates this with an HTTP PUT, so it can adopt and manage an
# organisation that already exists but cannot bring one into being. On an
# account that has never enabled Zero Trust the API answers "organisation not
# found". The team name is chosen once, out of band; from then on this owns it.
resource "cloudflare_zero_trust_organization" "this" {
  count = var.organization == null ? 0 : 1

  account_id  = var.account_id
  name        = local.organization.name
  auth_domain = local.organization.auth_domain

  session_duration                   = var.organization.session_duration
  auto_redirect_to_identity          = var.organization.auto_redirect_to_identity
  allow_authenticate_via_warp        = var.organization.allow_authenticate_via_warp
  is_ui_read_only                    = var.organization.is_ui_read_only
  ui_read_only_toggle_reason         = var.organization.ui_read_only_toggle_reason
  user_seat_expiration_inactive_time = var.organization.user_seat_expiration_inactive_time
  warp_auth_session_duration         = var.organization.warp_auth_session_duration
  login_design                       = var.organization.login_design
}

# Login methods. Renaming one destroys and recreates it, which invalidates every
# session opened through it, so the name is treated as identity here too.
resource "cloudflare_zero_trust_access_identity_provider" "this" {
  for_each = local.identity_providers

  account_id  = var.account_id
  name        = trimspace(each.value.name)
  type        = each.value.type
  config      = each.value.config
  scim_config = each.value.scim_config
}

# Machine credentials. The client secret Cloudflare generates is held in
# Terraform state in plain text and is not exposed as a module output.
resource "cloudflare_zero_trust_access_service_token" "this" {
  for_each = local.service_tokens

  account_id = var.account_id
  name       = trimspace(each.value.name)
  duration   = each.value.duration
}

# Reusable audiences.
resource "cloudflare_zero_trust_access_group" "this" {
  for_each = local.access_groups

  account_id = var.account_id
  name       = trimspace(each.value.name)
  is_default = each.value.is_default

  include = local.rule_terms_base["access_groups.${each.key}.include"]
  exclude = try(local.rule_terms_base["access_groups.${each.key}.exclude"], null)
  require = try(local.rule_terms_base["access_groups.${each.key}.require"], null)

  lifecycle {
    precondition {
      condition     = length(local.empty_group_rule_sets) == 0
      error_message = "These rule sets name no conditions at all: ${join("; ", local.empty_group_rule_sets)}. Cloudflare rejects an empty include, and an empty exclude or require is a restriction somebody believes is in force and is not. Remove the rule set or give it a condition."
    }

    precondition {
      condition     = length(local.unknown_service_token_names) == 0
      error_message = "service_token_names does not match any entry in var.service_tokens: ${join("; ", local.unknown_service_token_names)}. Declared tokens: ${join(", ", local.service_token_keys)}. Use service_token_ids for a token managed outside this module."
    }

    precondition {
      condition     = length(local.ambiguous_idp_references) == 0
      error_message = "These identity provider references set both identity_provider_name and identity_provider_id, or neither: ${join("; ", local.ambiguous_idp_references)}. Give exactly one - the name for a provider in var.identity_providers, the ID for one managed elsewhere."
    }

    precondition {
      condition     = length(local.unknown_identity_provider_references) == 0
      error_message = "These rules name an identity provider that is not in var.identity_providers: ${join("; ", local.unknown_identity_provider_references)}. Declared providers: ${join(", ", local.identity_provider_keys)}. Use identity_provider_id, or login_method_ids, for a provider managed outside this module."
    }
  }
}

# Reusable policies. Applications attach these by name.
resource "cloudflare_zero_trust_access_policy" "this" {
  for_each = local.access_policies

  account_id = var.account_id
  name       = trimspace(each.value.name)
  decision   = each.value.decision

  include = local.policy_rule_terms["access_policies.${each.key}.include"]
  exclude = try(local.policy_rule_terms["access_policies.${each.key}.exclude"], null)
  require = try(local.policy_rule_terms["access_policies.${each.key}.require"], null)

  session_duration               = each.value.session_duration
  isolation_required             = each.value.isolation_required
  purpose_justification_required = each.value.purpose_justification_required
  purpose_justification_prompt   = each.value.purpose_justification_prompt
  approval_required              = each.value.approval_required
  approval_groups                = length(each.value.approval_groups) > 0 ? each.value.approval_groups : null

  lifecycle {
    precondition {
      condition     = length(local.empty_policy_rule_sets) == 0
      error_message = "These rule sets name no conditions at all: ${join("; ", local.empty_policy_rule_sets)}. Cloudflare rejects an empty include, and an empty exclude or require is a restriction somebody believes is in force and is not. Remove the rule set or give it a condition."
    }

    precondition {
      condition     = length(local.unknown_group_names) == 0
      error_message = "group_names does not match any entry in var.access_groups: ${join("; ", local.unknown_group_names)}. Declared groups: ${join(", ", local.access_group_keys)}. Use group_ids for a group managed outside this module."
    }

    precondition {
      condition     = length(local.unknown_service_token_names) == 0
      error_message = "service_token_names does not match any entry in var.service_tokens: ${join("; ", local.unknown_service_token_names)}. Declared tokens: ${join(", ", local.service_token_keys)}. Use service_token_ids for a token managed outside this module."
    }

    precondition {
      condition     = length(local.ambiguous_idp_references) == 0
      error_message = "These identity provider references set both identity_provider_name and identity_provider_id, or neither: ${join("; ", local.ambiguous_idp_references)}. Give exactly one - the name for a provider in var.identity_providers, the ID for one managed elsewhere."
    }

    precondition {
      condition     = length(local.unknown_identity_provider_references) == 0
      error_message = "These rules name an identity provider that is not in var.identity_providers: ${join("; ", local.unknown_identity_provider_references)}. Declared providers: ${join(", ", local.identity_provider_keys)}. Use identity_provider_id, or login_method_ids, for a provider managed outside this module."
    }
  }
}

# The protected things themselves.
resource "cloudflare_zero_trust_access_application" "this" {
  for_each = local.access_applications

  account_id   = var.account_id
  name         = trimspace(each.value.name)
  type         = each.value.type
  domain       = each.value.domain
  destinations = length(local.application_destinations[each.key]) > 0 ? local.application_destinations[each.key] : null
  allowed_idps = length(local.application_allowed_idps[each.key]) > 0 ? toset(local.application_allowed_idps[each.key]) : null
  tags         = length(each.value.tags) > 0 ? toset(each.value.tags) : null

  policies = local.application_policies[each.key]

  session_duration            = each.value.session_duration
  auto_redirect_to_identity   = each.value.auto_redirect_to_identity
  app_launcher_visible        = each.value.app_launcher_visible
  enable_binding_cookie       = each.value.enable_binding_cookie
  http_only_cookie_attribute  = each.value.http_only_cookie_attribute
  same_site_cookie_attribute  = each.value.same_site_cookie_attribute
  path_cookie_attribute       = each.value.path_cookie_attribute
  custom_deny_message         = each.value.custom_deny_message
  custom_deny_url             = each.value.custom_deny_url
  skip_interstitial           = each.value.skip_interstitial
  service_auth_401_redirect   = each.value.service_auth_401_redirect
  options_preflight_bypass    = each.value.options_preflight_bypass
  allow_authenticate_via_warp = each.value.allow_authenticate_via_warp
  cors_headers                = each.value.cors_headers

  lifecycle {
    precondition {
      condition     = length(local.unknown_policy_names) == 0
      error_message = "policy_names does not match any entry in var.access_policies: ${join("; ", local.unknown_policy_names)}. Declared policies: ${join(", ", local.access_policy_keys)}. Use policy_ids for a policy managed outside this module."
    }

    precondition {
      condition     = length(local.unknown_application_idp_names) == 0
      error_message = "allowed_idp_names does not match any entry in var.identity_providers: ${join("; ", local.unknown_application_idp_names)}. Declared providers: ${join(", ", local.identity_provider_keys)}. Leave allowed_idp_names empty to offer every provider on the account."
    }

    # An application reachable by nobody looks identical to one that is simply
    # broken, and it is usually a policy list that lost its allow entry.
    precondition {
      condition     = length(local.applications_with_no_allowing_policy) == 0
      error_message = "Every policy attached to these applications refuses the request: ${join(", ", local.applications_with_no_allowing_policy)}. Nobody would be able to reach them. Attach a policy whose decision is allow, bypass or non_identity."
    }
  }
}
