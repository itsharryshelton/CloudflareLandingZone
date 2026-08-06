locals {
  # Zero Trust organisation

  existing_auth_domain = lower(trimspace(try(data.cloudflare_zero_trust_organization.this.auth_domain, "")))

  existing_team_name = (
    local.existing_auth_domain == ""
    ? ""
    : trimsuffix(local.existing_auth_domain, ".cloudflareaccess.com")
  )

  configured_team_name = var.zero_trust_team_name == null ? "" : lower(trimspace(var.zero_trust_team_name))

  # Adopt what the account already has when the account tree names nothing
  effective_team_name = local.configured_team_name != "" ? local.configured_team_name : local.existing_team_name

  organization = local.effective_team_name == "" ? null : {
    team_name                          = local.effective_team_name
    name                               = var.zero_trust_organization_name
    session_duration                   = var.default_session_duration
    auto_redirect_to_identity          = var.auto_redirect_to_identity
    allow_authenticate_via_warp        = var.allow_authenticate_via_warp
    is_ui_read_only                    = var.lock_dashboard_to_read_only
    ui_read_only_toggle_reason         = var.ui_read_only_toggle_reason
    user_seat_expiration_inactive_time = var.user_seat_expiration_inactive_time
    warp_auth_session_duration         = var.default_warp_auth_session_duration
    login_design                       = var.login_design
  }

  # Key -> Cloudflare name

  identity_provider_names_by_key = { for key, provider in var.identity_providers : key => provider.name }
  access_group_names_by_key      = { for key, group in var.access_groups : key => group.name }
  service_token_names_by_key     = { for key, token in var.service_tokens : key => token.name }
  access_policy_names_by_key     = { for key, policy in var.access_policies : key => policy.name }

  # Module inputs

  # The client secret is merged in from the pipeline environment, never from a
  # file. An identity provider that needs no secret simply has no entry.
  identity_providers = [
    for key, provider in var.identity_providers : {
      name        = provider.name
      type        = provider.type
      config      = merge(provider.config, { client_secret = lookup(var.identity_provider_secrets, key, null) })
      scim_config = provider.scim_config
    }
  ]

  service_tokens = [
    for key, token in var.service_tokens : {
      name     = token.name
      duration = coalesce(token.duration, var.default_service_token_duration)
    }
  ]

  rule_sets = merge(
    { for key, group in var.access_groups : "access_groups.${key}.include" => group.include },
    { for key, group in var.access_groups : "access_groups.${key}.exclude" => group.exclude if group.exclude != null },
    { for key, group in var.access_groups : "access_groups.${key}.require" => group.require if group.require != null },
    { for key, policy in var.access_policies : "access_policies.${key}.include" => policy.include },
    { for key, policy in var.access_policies : "access_policies.${key}.exclude" => policy.exclude if policy.exclude != null },
    { for key, policy in var.access_policies : "access_policies.${key}.require" => policy.require if policy.require != null },
  )

  translated_rules = {
    for path, rule in local.rule_sets : path => {
      everyone                = rule.everyone
      emails                  = rule.emails
      email_domains           = rule.email_domains
      email_list_ids          = rule.email_list_ids
      ip_cidrs                = rule.ip_cidrs
      ip_list_ids             = rule.ip_list_ids
      country_codes           = rule.country_codes
      group_ids               = rule.group_ids
      service_token_ids       = rule.service_token_ids
      any_valid_service_token = rule.any_valid_service_token
      certificate             = rule.certificate
      common_names            = rule.common_names
      auth_methods            = rule.auth_methods
      device_posture_ids      = rule.device_posture_ids
      login_method_ids        = rule.login_method_ids
      external_evaluations    = rule.external_evaluations

      group_names = [
        for key in rule.group_keys : local.access_group_names_by_key[key]
        if contains(keys(local.access_group_names_by_key), key)
      ]

      service_token_names = [
        for key in rule.service_token_keys : local.service_token_names_by_key[key]
        if contains(keys(local.service_token_names_by_key), key)
      ]

      login_method_names = [
        for key in rule.login_method_keys : local.identity_provider_names_by_key[key]
        if contains(keys(local.identity_provider_names_by_key), key)
      ]

      entra_groups = [
        for item in rule.entra_groups : {
          identity_provider_name = item.identity_provider_key == null ? null : lookup(local.identity_provider_names_by_key, item.identity_provider_key, null)
          identity_provider_id   = item.identity_provider_id
          group_id               = item.group_id
        }
        if item.identity_provider_key == null || contains(keys(local.identity_provider_names_by_key), item.identity_provider_key)
      ]

      entra_auth_contexts = [
        for item in rule.entra_auth_contexts : {
          identity_provider_name = item.identity_provider_key == null ? null : lookup(local.identity_provider_names_by_key, item.identity_provider_key, null)
          identity_provider_id   = item.identity_provider_id
          id                     = item.id
          ac_id                  = item.ac_id
        }
        if item.identity_provider_key == null || contains(keys(local.identity_provider_names_by_key), item.identity_provider_key)
      ]

      saml_attributes = [
        for item in rule.saml_attributes : {
          identity_provider_name = item.identity_provider_key == null ? null : lookup(local.identity_provider_names_by_key, item.identity_provider_key, null)
          identity_provider_id   = item.identity_provider_id
          attribute_name         = item.attribute_name
          attribute_value        = item.attribute_value
        }
        if item.identity_provider_key == null || contains(keys(local.identity_provider_names_by_key), item.identity_provider_key)
      ]

      oidc_claims = [
        for item in rule.oidc_claims : {
          identity_provider_name = item.identity_provider_key == null ? null : lookup(local.identity_provider_names_by_key, item.identity_provider_key, null)
          identity_provider_id   = item.identity_provider_id
          claim_name             = item.claim_name
          claim_value            = item.claim_value
        }
        if item.identity_provider_key == null || contains(keys(local.identity_provider_names_by_key), item.identity_provider_key)
      ]
    }
  }

  access_groups = [
    for key, group in var.access_groups : {
      name       = group.name
      is_default = group.is_default
      include    = local.translated_rules["access_groups.${key}.include"]
      exclude    = try(local.translated_rules["access_groups.${key}.exclude"], null)
      require    = try(local.translated_rules["access_groups.${key}.require"], null)
    }
  ]

  access_policies = [
    for key, policy in var.access_policies : {
      name                           = policy.name
      decision                       = policy.decision
      session_duration               = policy.session_duration
      isolation_required             = policy.isolation_required
      purpose_justification_required = policy.purpose_justification_required
      purpose_justification_prompt   = policy.purpose_justification_prompt
      approval_required              = policy.approval_required
      approval_groups                = policy.approval_groups
      include                        = local.translated_rules["access_policies.${key}.include"]
      exclude                        = try(local.translated_rules["access_policies.${key}.exclude"], null)
      require                        = try(local.translated_rules["access_policies.${key}.require"], null)
    }
  ]

  access_applications = [
    for key, application in var.access_applications : {
      name                        = application.name
      type                        = application.type
      domain                      = application.domain
      extra_destinations          = application.extra_destinations
      policy_ids                  = application.policy_ids
      allowed_idp_ids             = application.allowed_idp_ids
      session_duration            = application.session_duration
      auto_redirect_to_identity   = application.auto_redirect_to_identity
      app_launcher_visible        = application.app_launcher_visible
      enable_binding_cookie       = application.enable_binding_cookie
      http_only_cookie_attribute  = application.http_only_cookie_attribute
      same_site_cookie_attribute  = application.same_site_cookie_attribute
      path_cookie_attribute       = application.path_cookie_attribute
      custom_deny_message         = application.custom_deny_message
      custom_deny_url             = application.custom_deny_url
      skip_interstitial           = application.skip_interstitial
      service_auth_401_redirect   = application.service_auth_401_redirect
      options_preflight_bypass    = application.options_preflight_bypass
      allow_authenticate_via_warp = application.allow_authenticate_via_warp
      tags                        = application.tags
      cors_headers                = application.cors_headers

      # Order is precedence: Cloudflare evaluates policies in the order given and
      # the first match decides, so this list is preserved rather than sorted.
      policy_names = [
        for policy_key in application.policy_keys : local.access_policy_names_by_key[policy_key]
        if contains(keys(local.access_policy_names_by_key), policy_key)
      ]

      allowed_idp_names = [
        for provider_key in application.allowed_idp_keys : local.identity_provider_names_by_key[provider_key]
        if contains(keys(local.identity_provider_names_by_key), provider_key)
      ]
    }
  ]

  # Derived assertions, consumed by preflight.tf

  unknown_group_keys = sort(distinct(flatten([
    for path, rule in local.rule_sets : [
      for key in rule.group_keys : "${path}.group_keys -> \"${key}\""
      if !contains(keys(local.access_group_names_by_key), key)
    ]
  ])))

  unknown_service_token_keys = sort(distinct(flatten([
    for path, rule in local.rule_sets : [
      for key in rule.service_token_keys : "${path}.service_token_keys -> \"${key}\""
      if !contains(keys(local.service_token_names_by_key), key)
    ]
  ])))

  # Every place a rule or an application names an identity provider by key,
  # gathered so one message covers all of them.
  identity_provider_key_references = flatten([
    [
      for path, rule in local.rule_sets : concat(
        [for key in rule.login_method_keys : "${path}.login_method_keys -> \"${key}\"" if !contains(keys(local.identity_provider_names_by_key), key)],
        [for item in rule.entra_groups : "${path}.entra_groups -> \"${item.identity_provider_key}\"" if item.identity_provider_key != null && !contains(keys(local.identity_provider_names_by_key), item.identity_provider_key)],
        [for item in rule.entra_auth_contexts : "${path}.entra_auth_contexts -> \"${item.identity_provider_key}\"" if item.identity_provider_key != null && !contains(keys(local.identity_provider_names_by_key), item.identity_provider_key)],
        [for item in rule.saml_attributes : "${path}.saml_attributes -> \"${item.identity_provider_key}\"" if item.identity_provider_key != null && !contains(keys(local.identity_provider_names_by_key), item.identity_provider_key)],
        [for item in rule.oidc_claims : "${path}.oidc_claims -> \"${item.identity_provider_key}\"" if item.identity_provider_key != null && !contains(keys(local.identity_provider_names_by_key), item.identity_provider_key)],
      )
    ],
    [
      for key, application in var.access_applications : [
        for provider_key in application.allowed_idp_keys : "access_applications.${key}.allowed_idp_keys -> \"${provider_key}\""
        if !contains(keys(local.identity_provider_names_by_key), provider_key)
      ]
    ],
  ])

  unknown_identity_provider_keys = sort(distinct(local.identity_provider_key_references))

  unknown_policy_keys = sort(distinct(flatten([
    for key, application in var.access_applications : [
      for policy_key in application.policy_keys : "access_applications.${key}.policy_keys -> \"${policy_key}\""
      if !contains(keys(local.access_policy_names_by_key), policy_key)
    ]
  ])))

  # Both identity_provider_key and identity_provider_id, or neither. Preferring
  # one silently would make the other look effective when it is not.
  ambiguous_identity_provider_references = sort(distinct(flatten([
    for path, rule in local.rule_sets : concat(
      [for item in rule.entra_groups : "${path}.entra_groups" if(item.identity_provider_key == null) == (item.identity_provider_id == null)],
      [for item in rule.entra_auth_contexts : "${path}.entra_auth_contexts" if(item.identity_provider_key == null) == (item.identity_provider_id == null)],
      [for item in rule.saml_attributes : "${path}.saml_attributes" if(item.identity_provider_key == null) == (item.identity_provider_id == null)],
      [for item in rule.oidc_claims : "${path}.oidc_claims" if(item.identity_provider_key == null) == (item.identity_provider_id == null)],
    )
  ])))

  restricted_policy_decisions = [for decision in var.restricted_policy_decisions : lower(trimspace(decision))]

  restricted_decisions_used = sort([
    for key, policy in var.access_policies : "access_policies.${key} -> \"${policy.decision}\""
    if contains(local.restricted_policy_decisions, lower(trimspace(policy.decision)))
  ])

  allowed_email_domains = [for domain in var.allowed_email_domains : lower(trimspace(domain))]

  # Only `include` grants access. An exclude or a require naming an outside
  # domain narrows the audience rather than widening it, so it is left alone.
  disallowed_email_references = length(local.allowed_email_domains) == 0 ? [] : sort(distinct(flatten([
    for path, rule in local.rule_sets : concat(
      [
        for domain in rule.email_domains : "${path}.email_domains -> ${lower(trimspace(domain))}"
        if !contains(local.allowed_email_domains, lower(trimspace(domain)))
      ],
      [
        for email in rule.emails : "${path}.emails -> ${lower(trimspace(email))}"
        if !contains(local.allowed_email_domains, try(split("@", lower(trimspace(email)))[1], ""))
      ],
    )
    if endswith(path, ".include")
  ])))

  # Login methods that authenticate against an OAuth application and therefore
  # need a client secret. SAML and the one-time PIN do not.
  oauth_identity_provider_types = [
    "azureAD", "oidc", "okta", "onelogin", "pingone", "centrify",
    "google", "google-apps", "github", "facebook", "linkedin", "yandex",
  ]

  # Only the keys are read, never a value, so the result carries no sensitivity
  # into a precondition message.
  identity_provider_secret_keys = nonsensitive(keys(var.identity_provider_secrets))

  identity_providers_missing_secret = sort([
    for key, provider in var.identity_providers : "identity_providers.${key} (${provider.type})"
    if contains(local.oauth_identity_provider_types, provider.type) && !contains(local.identity_provider_secret_keys, key)
  ])

  orphaned_identity_provider_secrets = sort([
    for key in local.identity_provider_secret_keys : key
    if !contains(keys(var.identity_providers), key)
  ])

  team_name_conflict = (
    local.configured_team_name != "" &&
    local.existing_team_name != "" &&
    local.configured_team_name != local.existing_team_name
  )
}
