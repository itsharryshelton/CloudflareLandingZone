locals {
  # Zero Trust organisation
  team_name = var.organization == null ? null : lower(trimspace(var.organization.team_name))

  organization = var.organization == null ? null : {
    name        = trimspace(coalesce(var.organization.name, local.team_name))
    auth_domain = "${local.team_name}.cloudflareaccess.com"
  }

  # Collections, keyed on the Cloudflare-visible name
  identity_providers     = { for p in var.identity_providers : lower(trimspace(p.name)) => p }
  identity_provider_keys = keys(local.identity_providers)

  service_tokens     = { for t in var.service_tokens : lower(trimspace(t.name)) => t }
  service_token_keys = keys(local.service_tokens)

  access_groups     = { for g in var.access_groups : lower(trimspace(g.name)) => g }
  access_group_keys = keys(local.access_groups)

  access_policies    = { for p in var.access_policies : lower(trimspace(p.name)) => p }
  access_policy_keys = keys(local.access_policies)

  access_applications = { for a in var.access_applications : lower(trimspace(a.name)) => a }

  identity_provider_ids_by_name = {
    for key in local.identity_provider_keys : key => cloudflare_zero_trust_access_identity_provider.this[key].id
  }

  # Rule sets
  rule_sets = merge(
    { for key, group in local.access_groups : "access_groups.${key}.include" => group.include },
    { for key, group in local.access_groups : "access_groups.${key}.exclude" => group.exclude if group.exclude != null },
    { for key, group in local.access_groups : "access_groups.${key}.require" => group.require if group.require != null },
    { for key, policy in local.access_policies : "access_policies.${key}.include" => policy.include },
    { for key, policy in local.access_policies : "access_policies.${key}.exclude" => policy.exclude if policy.exclude != null },
    { for key, policy in local.access_policies : "access_policies.${key}.require" => policy.require if policy.require != null },
  )

  # Every identity-provider-bearing condition, flattened onto a common shape so
  # the "name or ID, not both" rule is expressed once rather than four times.
  rule_sets_normalised = {
    for path, rule in local.rule_sets : path => merge(rule, {
      entra_groups = [for item in rule.entra_groups : {
        group_id = item.group_id
        idp_id   = item.identity_provider_id
        idp_key  = item.identity_provider_name == null ? "" : lower(trimspace(item.identity_provider_name))
      }]
      entra_auth_contexts = [for item in rule.entra_auth_contexts : {
        id      = item.id
        ac_id   = item.ac_id
        idp_id  = item.identity_provider_id
        idp_key = item.identity_provider_name == null ? "" : lower(trimspace(item.identity_provider_name))
      }]
      saml_attributes = [for item in rule.saml_attributes : {
        attribute_name  = item.attribute_name
        attribute_value = item.attribute_value
        idp_id          = item.identity_provider_id
        idp_key         = item.identity_provider_name == null ? "" : lower(trimspace(item.identity_provider_name))
      }]
      oidc_claims = [for item in rule.oidc_claims : {
        claim_name  = item.claim_name
        claim_value = item.claim_value
        idp_id      = item.identity_provider_id
        idp_key     = item.identity_provider_name == null ? "" : lower(trimspace(item.identity_provider_name))
      }]
    })
  }

  # Conditions expressed without any reference to an Access group this module
  # creates. Safe for access groups and policies alike.
  rule_terms_base = {
    for path, rule in local.rule_sets_normalised : path => concat(
      rule.everyone ? [{ everyone = {} }] : [],
      rule.any_valid_service_token ? [{ any_valid_service_token = {} }] : [],
      rule.certificate ? [{ certificate = {} }] : [],
      [for email in rule.emails : { email = { email = lower(trimspace(email)) } }],
      [for domain in rule.email_domains : { email_domain = { domain = lower(trimspace(domain)) } }],
      [for id in rule.email_list_ids : { email_list = { id = id } }],
      [for cidr in rule.ip_cidrs : { ip = { ip = cidr } }],
      [for id in rule.ip_list_ids : { ip_list = { id = id } }],
      [for code in rule.country_codes : { geo = { country_code = upper(trimspace(code)) } }],
      [for id in rule.group_ids : { group = { id = id } }],
      [
        for name in rule.service_token_names :
        { service_token = { token_id = cloudflare_zero_trust_access_service_token.this[lower(trimspace(name))].id } }
        if contains(local.service_token_keys, lower(trimspace(name)))
      ],
      [for id in rule.service_token_ids : { service_token = { token_id = id } }],
      [for name in rule.common_names : { common_name = { common_name = name } }],
      [for method in rule.auth_methods : { auth_method = { auth_method = method } }],
      [for id in rule.device_posture_ids : { device_posture = { integration_uid = id } }],
      [
        for name in rule.login_method_names :
        { login_method = { id = local.identity_provider_ids_by_name[lower(trimspace(name))] } }
        if contains(local.identity_provider_keys, lower(trimspace(name)))
      ],
      [for id in rule.login_method_ids : { login_method = { id = id } }],
      [
        for item in rule.entra_groups : {
          azure_ad = {
            id                   = item.group_id
            identity_provider_id = item.idp_id != null ? item.idp_id : local.identity_provider_ids_by_name[item.idp_key]
          }
        }
        if item.idp_id != null || contains(local.identity_provider_keys, item.idp_key)
      ],
      [
        for item in rule.entra_auth_contexts : {
          auth_context = {
            id                   = item.id
            ac_id                = item.ac_id
            identity_provider_id = item.idp_id != null ? item.idp_id : local.identity_provider_ids_by_name[item.idp_key]
          }
        }
        if item.idp_id != null || contains(local.identity_provider_keys, item.idp_key)
      ],
      [
        for item in rule.saml_attributes : {
          saml = {
            attribute_name       = item.attribute_name
            attribute_value      = item.attribute_value
            identity_provider_id = item.idp_id != null ? item.idp_id : local.identity_provider_ids_by_name[item.idp_key]
          }
        }
        if item.idp_id != null || contains(local.identity_provider_keys, item.idp_key)
      ],
      [
        for item in rule.oidc_claims : {
          oidc = {
            claim_name           = item.claim_name
            claim_value          = item.claim_value
            identity_provider_id = item.idp_id != null ? item.idp_id : local.identity_provider_ids_by_name[item.idp_key]
          }
        }
        if item.idp_id != null || contains(local.identity_provider_keys, item.idp_key)
      ],
      [
        for item in rule.external_evaluations :
        { external_evaluation = { evaluate_url = item.evaluate_url, keys_url = item.keys_url } }
      ],
    )
  }

  # Resolved separately, and consumed only by policies. See the header.
  rule_terms_group_names = {
    for path, rule in local.rule_sets_normalised : path => [
      for name in rule.group_names :
      { group = { id = cloudflare_zero_trust_access_group.this[lower(trimspace(name))].id } }
      if contains(local.access_group_keys, lower(trimspace(name)))
    ]
  }

  policy_rule_terms = {
    for path, terms in local.rule_terms_base : path => concat(terms, local.rule_terms_group_names[path])
  }

  # Access applications

  # Precedence is the position in the list: Cloudflare evaluates policies in
  # order and the first match decides, so an operator reordering policy_names is
  # making a real change and should see it in the plan.
  application_policies = {
    for key, application in local.access_applications : key => concat(
      [
        for index, name in application.policy_names : {
          id         = cloudflare_zero_trust_access_policy.this[lower(trimspace(name))].id
          precedence = index + 1
        }
        if contains(local.access_policy_keys, lower(trimspace(name)))
      ],
      [
        for index, id in application.policy_ids : {
          id         = id
          precedence = length(application.policy_names) + index + 1
        }
      ],
    )
  }

  # `destinations` replaced the deprecated `self_hosted_domains`.
  # `domain` is only the primary hostname shown in the App Launcher, so it must appear in the list too, otherwise the application's own hostname stops being protected.
  # Every entry carries the full key set because Terraform needs one object type across the list, and `distinct` needs it to compare them at all.
  application_destinations = {
    for key, application in local.access_applications : key => distinct(concat(
      application.domain == null || trimspace(coalesce(application.domain, "")) == "" ? [] : [{
        type        = "public"
        uri         = trimspace(application.domain)
        hostname    = null
        cidr        = null
        l4_protocol = null
        port_range  = null
        vnet_id     = null
      }],
      [
        for destination in application.extra_destinations : {
          type        = destination.type
          uri         = destination.uri == null ? null : trimspace(destination.uri)
          hostname    = destination.hostname
          cidr        = destination.cidr
          l4_protocol = destination.l4_protocol
          port_range  = destination.port_range
          vnet_id     = destination.vnet_id
        }
      ],
    ))
  }

  application_allowed_idps = {
    for key, application in local.access_applications : key => distinct(concat(
      [
        for name in application.allowed_idp_names : local.identity_provider_ids_by_name[lower(trimspace(name))]
        if contains(local.identity_provider_keys, lower(trimspace(name)))
      ],
      application.allowed_idp_ids,
    ))
  }

  # Derived assertions, consumed by the preconditions in main.tf

  idp_references = flatten([
    for path, rule in local.rule_sets_normalised : concat(
      [for item in rule.entra_groups : { path = path, field = "entra_groups", idp_id = item.idp_id, idp_key = item.idp_key }],
      [for item in rule.entra_auth_contexts : { path = path, field = "entra_auth_contexts", idp_id = item.idp_id, idp_key = item.idp_key }],
      [for item in rule.saml_attributes : { path = path, field = "saml_attributes", idp_id = item.idp_id, idp_key = item.idp_key }],
      [for item in rule.oidc_claims : { path = path, field = "oidc_claims", idp_id = item.idp_id, idp_key = item.idp_key }],
    )
  ])

  ambiguous_idp_references = distinct([
    for reference in local.idp_references : "${reference.path}.${reference.field}"
    if(reference.idp_id == null) == (reference.idp_key == "")
  ])

  unknown_idp_names = distinct([
    for reference in local.idp_references : "${reference.path}.${reference.field} -> \"${reference.idp_key}\""
    if reference.idp_id == null && reference.idp_key != "" && !contains(local.identity_provider_keys, reference.idp_key)
  ])

  unknown_identity_provider_references = sort(distinct(concat(
    local.unknown_idp_names,
    local.unknown_login_method_names,
  )))

  unknown_group_names = distinct(flatten([
    for path, rule in local.rule_sets_normalised : [
      for name in rule.group_names : "${path}.group_names -> \"${name}\""
      if !contains(local.access_group_keys, lower(trimspace(name)))
    ]
  ]))

  unknown_service_token_names = distinct(flatten([
    for path, rule in local.rule_sets_normalised : [
      for name in rule.service_token_names : "${path}.service_token_names -> \"${name}\""
      if !contains(local.service_token_keys, lower(trimspace(name)))
    ]
  ]))

  unknown_login_method_names = distinct(flatten([
    for path, rule in local.rule_sets_normalised : [
      for name in rule.login_method_names : "${path}.login_method_names -> \"${name}\""
      if !contains(local.identity_provider_keys, lower(trimspace(name)))
    ]
  ]))

  unknown_policy_names = distinct(flatten([
    for key, application in local.access_applications : [
      for name in application.policy_names : "access_applications.${key}.policy_names -> \"${name}\""
      if !contains(local.access_policy_keys, lower(trimspace(name)))
    ]
  ]))

  unknown_application_idp_names = distinct(flatten([
    for key, application in local.access_applications : [
      for name in application.allowed_idp_names : "access_applications.${key}.allowed_idp_names -> \"${name}\""
      if !contains(local.identity_provider_keys, lower(trimspace(name)))
    ]
  ]))

  # A rule set that expands to nothing. Cloudflare rejects an empty.
  empty_group_rule_sets = sort([
    for path, terms in local.rule_terms_base : path
    if startswith(path, "access_groups.") && length(terms) == 0
  ])

  empty_policy_rule_sets = sort([
    for path, terms in local.policy_rule_terms : path
    if startswith(path, "access_policies.") && length(terms) == 0
  ])

  applications_with_no_allowing_policy = sort([
    for key, application in local.access_applications : key
    if length(application.policy_ids) == 0 && !anytrue([
      for name in application.policy_names :
      contains(["allow", "bypass", "non_identity"], local.access_policies[lower(trimspace(name))].decision)
      if contains(local.access_policy_keys, lower(trimspace(name)))
    ])
  ])
}
