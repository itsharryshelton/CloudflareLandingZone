variable "account_id" {
  type        = string
  description = "Cloudflare Account ID whose Zero Trust organization, Access applications, policies, groups, service tokens and identity providers this module manages."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "organization" {
  type = object({
    team_name                          = string
    name                               = optional(string)
    session_duration                   = optional(string)
    auto_redirect_to_identity          = optional(bool)
    allow_authenticate_via_warp        = optional(bool)
    is_ui_read_only                    = optional(bool)
    ui_read_only_toggle_reason         = optional(string)
    user_seat_expiration_inactive_time = optional(string)
    warp_auth_session_duration         = optional(string)
    login_design = optional(object({
      background_color = optional(string)
      footer_text      = optional(string)
      header_text      = optional(string)
      logo_path        = optional(string)
      text_color       = optional(string)
    }))
  })
  default     = null
  description = <<-EOT
    The account's Zero Trust organization: the team name every Access login page,
    WARP enrolment and service token lives under. Leave null to manage Access
    objects without touching organization-wide settings.

      - team_name                          : the subdomain half of the team domain.
                                             "acme" gives acme.cloudflareaccess.com.
                                             Lower-case letters, digits and hyphens.
                                             THIS IS NOT A FREE EDIT - see below.
      - name                               : (Optional) display name. Defaults to team_name.
      - session_duration                   : (Optional) how long an Access session lasts
                                             before re-authentication, e.g. "24h". Applies
                                             to any application that sets none of its own.
      - auto_redirect_to_identity          : (Optional) skip the identity provider chooser
                                             when only one provider makes sense.
      - allow_authenticate_via_warp        : (Optional) let a WARP-enrolled device satisfy
                                             authentication without a browser login.
      - is_ui_read_only                    : (Optional) lock every Zero Trust setting in the
                                             dashboard to read-only, for everybody, whatever
                                             their role. Set it true wherever Terraform is
                                             meant to be the only way in - it turns a
                                             dashboard hotfix into a pull request.
      - ui_read_only_toggle_reason         : (Optional) the reason recorded when the lock
                                             above is lifted.
      - user_seat_expiration_inactive_time : (Optional) how long a seat survives without a
                                             login before it is released, e.g. "730h".
                                             Cloudflare's minimum is 730h.
      - warp_auth_session_duration         : (Optional) WARP token validity, e.g. "24h".
      - login_design                       : (Optional) branding for the Access login page.

    Changing team_name renames the team domain. Every Access application URL,
    every enrolled WARP client and every bookmark that points at
    <old>.cloudflareaccess.com stops resolving, and the old name is released for
    anyone else to claim. Treat it as a migration, not a rename.

    This module can only manage an organization that already exists. The provider
    creates it with an HTTP PUT, which the Cloudflare API rejects on an account
    that has never enabled Zero Trust - so the team name has to be chosen once,
    out of band. The layer that calls this module fails the plan with the exact
    steps rather than letting the apply fall over.
  EOT

  validation {
    condition = (
      var.organization == null ||
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", try(var.organization.team_name, "")))
    )
    error_message = "organization.team_name must be 1-63 characters of lower-case letters, digits and hyphens, not starting or ending with a hyphen. It becomes <team_name>.cloudflareaccess.com."
  }

  validation {
    condition = (
      var.organization == null ||
      try(var.organization.session_duration, null) == null ||
      can(regex("^([0-9]+(ns|us|ms|s|m|h))+$", try(var.organization.session_duration, "")))
    )
    error_message = "organization.session_duration must be a Go duration such as \"24h\", \"2h45m\" or \"300ms\"."
  }

  validation {
    condition = (
      var.organization == null ||
      try(var.organization.warp_auth_session_duration, null) == null ||
      can(regex("^([0-9]+(ns|us|ms|s|m|h))+$", try(var.organization.warp_auth_session_duration, "")))
    )
    error_message = "organization.warp_auth_session_duration must be a Go duration such as \"24h\" or \"30m\"."
  }

  validation {
    condition = (
      var.organization == null ||
      try(var.organization.user_seat_expiration_inactive_time, null) == null ||
      can(regex("^([0-9]+(ns|us|ms|s|m|h))+$", try(var.organization.user_seat_expiration_inactive_time, "")))
    )
    error_message = "organization.user_seat_expiration_inactive_time must be a Go duration such as \"730h\". Cloudflare's minimum is 730h."
  }
}

variable "identity_providers" {
  type = list(object({
    name = string
    type = string
    config = optional(object({
      client_id                  = optional(string)
      client_secret              = optional(string)
      directory_id               = optional(string)
      support_groups             = optional(bool)
      conditional_access_enabled = optional(bool)
      prompt                     = optional(string)
      claims                     = optional(list(string))
      email_claim_name           = optional(string)
      scopes                     = optional(list(string))
      auth_url                   = optional(string)
      token_url                  = optional(string)
      certs_url                  = optional(string)
      issuer_url                 = optional(string)
      sso_target_url             = optional(string)
      idp_public_certs           = optional(list(string))
      attributes                 = optional(list(string))
      email_attribute_name       = optional(string)
      sign_request               = optional(bool)
      pkce_enabled               = optional(bool)
    }), {})
    scim_config = optional(object({
      enabled                  = optional(bool)
      identity_update_behavior = optional(string)
      seat_deprovision         = optional(bool)
      user_deprovision         = optional(bool)
    }))
  }))
  default     = []
  description = <<-EOT
    Login methods Access offers. Rules elsewhere in this module reference a
    provider by `name`, so a provider and the rules that use it can be created in
    one apply.

      - name        : display name on the login page, and this provider's identity
                      here. Matched lower-cased and trimmed. Renaming destroys and
                      recreates it, which invalidates every session opened through it.
      - type        : "azureAD" for Microsoft Entra ID, "onetimepin" for the built-in
                      email PIN, or one of "saml", "oidc", "google", "google-apps",
                      "okta", "onelogin", "pingone", "centrify", "github",
                      "facebook", "linkedin", "yandex", "cloudflare".
      - config      : provider-specific settings. For Entra ID:
                        client_id                  - the Entra app registration's Application (client) ID
                        client_secret              - that app registration's client secret. A CREDENTIAL.
                                                     It must arrive from a pipeline secret, never a
                                                     committed .tfvars, and it is stored in plain text in
                                                     Terraform state either way.
                        directory_id               - the Entra tenant (directory) ID
                        support_groups             - pull group membership into Access, which is what
                                                     makes entra_groups usable in a rule
                        conditional_access_enabled - pull Entra Conditional Access authentication
                                                     contexts through, for entra_auth_contexts
                        prompt                     - "login", "select_account" or "none"
                      "onetimepin" takes no config at all.
      - scim_config : (Optional) SCIM user and group provisioning from the provider.
                      seat_deprovision and user_deprovision remove Cloudflare access
                      when the upstream directory removes the person, which is the
                      point of turning it on.

    Deleting an entry removes the login method. Anybody who can only authenticate
    that way loses access on the next apply.
  EOT

  validation {
    condition     = alltrue([for p in var.identity_providers : trimspace(p.name) != ""])
    error_message = "Each identity_providers[*].name must be a non-empty display name."
  }

  validation {
    condition = length(distinct([
      for p in var.identity_providers : lower(trimspace(p.name))
    ])) == length(var.identity_providers)
    error_message = "identity_providers contains duplicate names. Names are compared lower-cased and trimmed, and they are how a rule refers to a provider - each provider must be uniquely named."
  }

  # The enum is inlined rather than held in a local because variable validation
  # cannot reference locals, and TFLint deletes a local nothing else reads.
  validation {
    condition = alltrue([
      for p in var.identity_providers : contains([
        "onetimepin", "azureAD", "saml", "centrify", "facebook", "github",
        "google-apps", "google", "linkedin", "oidc", "okta", "onelogin",
        "pingone", "yandex", "cloudflare",
      ], p.type)
    ])
    error_message = "Each identity_providers[*].type must be one of onetimepin, azureAD, saml, centrify, facebook, github, google-apps, google, linkedin, oidc, okta, onelogin, pingone, yandex, cloudflare. Microsoft Entra ID is \"azureAD\" - the value kept its Azure AD name."
  }

  validation {
    condition = alltrue([
      for p in var.identity_providers :
      try(p.config.prompt, null) == null ? true : contains(["login", "select_account", "none"], p.config.prompt)
    ])
    error_message = "identity_providers[*].config.prompt must be \"login\", \"select_account\" or \"none\" when set."
  }

  validation {
    condition = alltrue([
      for p in var.identity_providers :
      try(p.scim_config.identity_update_behavior, null) == null ? true : contains(["automatic", "reauth", "no_action"], p.scim_config.identity_update_behavior)
    ])
    error_message = "identity_providers[*].scim_config.identity_update_behavior must be \"automatic\", \"reauth\" or \"no_action\" when set."
  }
}

variable "service_tokens" {
  type = list(object({
    name     = string
    duration = optional(string)
  }))
  default     = []
  description = <<-EOT
    Non-human credentials. A service token is a client ID and secret pair that a
    machine presents in CF-Access-Client-Id and CF-Access-Client-Secret headers
    to reach an application without a browser login.

      - name     : the token's display name and its identity here, matched
                   lower-cased and trimmed. Renaming destroys and recreates the
                   token, which issues a new secret and breaks every caller still
                   holding the old one.
      - duration : (Optional) how long the token stays valid, e.g. "8760h" for a
                   year. Cloudflare also accepts "forever", which this module
                   allows but does not encourage: a credential with no expiry is
                   one nobody is ever forced to rotate.

    The generated client secret is shown by Cloudflare exactly once, and lands in
    Terraform state in plain text. It is deliberately not exposed as an output of
    this module - read it from the dashboard or from state, hand it to the caller
    through a secret store, and treat state as a credential store from then on.
  EOT

  validation {
    condition     = alltrue([for t in var.service_tokens : trimspace(t.name) != ""])
    error_message = "Each service_tokens[*].name must be a non-empty display name."
  }

  validation {
    condition = length(distinct([
      for t in var.service_tokens : lower(trimspace(t.name))
    ])) == length(var.service_tokens)
    error_message = "service_tokens contains duplicate names. Names are compared lower-cased and trimmed, and they are how a rule refers to a token - each token must be uniquely named."
  }

  validation {
    condition = alltrue([
      for t in var.service_tokens :
      t.duration == null ? true : (t.duration == "forever" || can(regex("^([0-9]+(ns|us|ms|s|m|h))+$", t.duration)))
    ])
    error_message = "Each service_tokens[*].duration must be a Go duration such as \"8760h\", or the literal \"forever\"."
  }
}

variable "access_groups" {
  type = list(object({
    name       = string
    is_default = optional(bool)
    include = object({
      everyone                = optional(bool, false)
      emails                  = optional(list(string), [])
      email_domains           = optional(list(string), [])
      email_list_ids          = optional(list(string), [])
      ip_cidrs                = optional(list(string), [])
      ip_list_ids             = optional(list(string), [])
      country_codes           = optional(list(string), [])
      group_names             = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_names     = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_names      = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        group_id               = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        id                     = string
        ac_id                  = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        attribute_name         = string
        attribute_value        = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        claim_name             = string
        claim_value            = string
      })), [])
      external_evaluations = optional(list(object({
        evaluate_url = string
        keys_url     = string
      })), [])
    })
    exclude = optional(object({
      everyone                = optional(bool, false)
      emails                  = optional(list(string), [])
      email_domains           = optional(list(string), [])
      email_list_ids          = optional(list(string), [])
      ip_cidrs                = optional(list(string), [])
      ip_list_ids             = optional(list(string), [])
      country_codes           = optional(list(string), [])
      group_names             = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_names     = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_names      = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        group_id               = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        id                     = string
        ac_id                  = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        attribute_name         = string
        attribute_value        = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        claim_name             = string
        claim_value            = string
      })), [])
      external_evaluations = optional(list(object({
        evaluate_url = string
        keys_url     = string
      })), [])
    }))
    require = optional(object({
      everyone                = optional(bool, false)
      emails                  = optional(list(string), [])
      email_domains           = optional(list(string), [])
      email_list_ids          = optional(list(string), [])
      ip_cidrs                = optional(list(string), [])
      ip_list_ids             = optional(list(string), [])
      country_codes           = optional(list(string), [])
      group_names             = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_names     = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_names      = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        group_id               = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        id                     = string
        ac_id                  = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        attribute_name         = string
        attribute_value        = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        claim_name             = string
        claim_value            = string
      })), [])
      external_evaluations = optional(list(object({
        evaluate_url = string
        keys_url     = string
      })), [])
    }))
  }))
  default     = []
  description = <<-EOT
    Reusable sets of people and conditions. A group is named once and referenced
    by every policy that needs the same audience, so "who counts as an
    administrator" is answered in one place instead of copied into eight policies.

      - name       : display name and identity here, matched lower-cased and
                     trimmed. Renaming destroys and recreates the group; policies
                     referencing it by name follow, policies referencing it by ID
                     do not.
      - is_default : (Optional) add this group to every new Access application
                     created afterwards. Off unless you mean it.
      - include    : match any one of these and the group matches. Required.
      - exclude    : (Optional) match any one of these and the group does not
                     match, whatever include said. Exclude beats include.
      - require    : (Optional) every condition here must hold as well.

    A rule set is an OR across everything named in it:

      everyone                - matches any successfully authenticated identity
      emails                  - exact addresses
      email_domains           - everybody at a domain, e.g. "example.com"
      email_list_ids          - a Cloudflare list of addresses, by ID
      ip_cidrs                - source IP ranges in CIDR form
      ip_list_ids             - a Cloudflare list of IPs, by ID
      country_codes           - two-letter ISO country codes
      group_names             - other Access groups. NOT AVAILABLE HERE - see below.
      group_ids               - Access groups managed outside this module, by ID
      service_token_names     - service tokens from var.service_tokens
      service_token_ids       - service tokens managed elsewhere, by ID
      any_valid_service_token - any service token on the account
      certificate             - a valid client certificate (mTLS)
      common_names            - a client certificate with this CN
      auth_methods            - AMR values from the identity provider, e.g. "mfa", "swk"
      device_posture_ids      - device posture rule IDs from WARP
      login_method_names      - restrict to specific providers from var.identity_providers
      login_method_ids        - the same, for a provider managed elsewhere
      entra_groups            - a Microsoft Entra ID group's object ID, per provider
      entra_auth_contexts     - an Entra Conditional Access authentication context
      saml_attributes         - a SAML attribute name and value
      oidc_claims             - an OIDC claim name and value
      external_evaluations    - hand the decision to an external service

    Every reference that takes an identity provider accepts either
    identity_provider_name, resolved against var.identity_providers, or
    identity_provider_id for one managed elsewhere. Exactly one of the two.

    group_names is rejected inside access_groups on purpose. A group nesting
    another group this module also creates is a dependency Terraform would have
    to resolve while it is still deciding what the groups are, and it would fail
    as a cycle rather than as anything readable. Nest an externally managed group
    with group_ids, or flatten the two groups into one rule set.
  EOT

  validation {
    condition     = alltrue([for g in var.access_groups : trimspace(g.name) != ""])
    error_message = "Each access_groups[*].name must be a non-empty display name."
  }

  validation {
    condition = length(distinct([
      for g in var.access_groups : lower(trimspace(g.name))
    ])) == length(var.access_groups)
    error_message = "access_groups contains duplicate names. Names are compared lower-cased and trimmed, and they are how a policy refers to a group - each group must be uniquely named."
  }

  validation {
    condition = alltrue(flatten([
      for g in var.access_groups : [
        for rule in [g.include, g.exclude, g.require] : length(rule.group_names) == 0
        if rule != null
      ]
    ]))
    error_message = "access_groups[*] rules must not use group_names. A group referencing another group created by this module is a Terraform dependency cycle, not a configuration error Cloudflare would report. Use group_ids for a group managed outside this module, or merge the two rule sets."
  }

  validation {
    condition = alltrue(flatten([
      for g in var.access_groups : [
        for rule in [g.include, g.exclude, g.require] : [
          for code in rule.country_codes : can(regex("^[A-Za-z]{2}$", code))
        ]
        if rule != null
      ]
    ]))
    error_message = "Each access_groups[*] country_codes entry must be a two-letter ISO 3166-1 country code, for example \"GB\"."
  }

  validation {
    condition = alltrue(flatten([
      for g in var.access_groups : [
        for rule in [g.include, g.exclude, g.require] : [
          for cidr in rule.ip_cidrs : can(cidrnetmask(cidr))
        ]
        if rule != null
      ]
    ]))
    error_message = "Each access_groups[*] ip_cidrs entry must be a CIDR range such as 203.0.113.0/24. A bare address needs an explicit /32."
  }
}

variable "access_policies" {
  type = list(object({
    name                           = string
    decision                       = string
    session_duration               = optional(string)
    isolation_required             = optional(bool)
    purpose_justification_required = optional(bool)
    purpose_justification_prompt   = optional(string)
    approval_required              = optional(bool)
    approval_groups = optional(list(object({
      approvals_needed = number
      email_addresses  = optional(list(string))
      email_list_uuid  = optional(string)
    })), [])
    include = object({
      everyone                = optional(bool, false)
      emails                  = optional(list(string), [])
      email_domains           = optional(list(string), [])
      email_list_ids          = optional(list(string), [])
      ip_cidrs                = optional(list(string), [])
      ip_list_ids             = optional(list(string), [])
      country_codes           = optional(list(string), [])
      group_names             = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_names     = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_names      = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        group_id               = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        id                     = string
        ac_id                  = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        attribute_name         = string
        attribute_value        = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        claim_name             = string
        claim_value            = string
      })), [])
      external_evaluations = optional(list(object({
        evaluate_url = string
        keys_url     = string
      })), [])
    })
    exclude = optional(object({
      everyone                = optional(bool, false)
      emails                  = optional(list(string), [])
      email_domains           = optional(list(string), [])
      email_list_ids          = optional(list(string), [])
      ip_cidrs                = optional(list(string), [])
      ip_list_ids             = optional(list(string), [])
      country_codes           = optional(list(string), [])
      group_names             = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_names     = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_names      = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        group_id               = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        id                     = string
        ac_id                  = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        attribute_name         = string
        attribute_value        = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        claim_name             = string
        claim_value            = string
      })), [])
      external_evaluations = optional(list(object({
        evaluate_url = string
        keys_url     = string
      })), [])
    }))
    require = optional(object({
      everyone                = optional(bool, false)
      emails                  = optional(list(string), [])
      email_domains           = optional(list(string), [])
      email_list_ids          = optional(list(string), [])
      ip_cidrs                = optional(list(string), [])
      ip_list_ids             = optional(list(string), [])
      country_codes           = optional(list(string), [])
      group_names             = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_names     = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_names      = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        group_id               = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        id                     = string
        ac_id                  = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        attribute_name         = string
        attribute_value        = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_name = optional(string)
        identity_provider_id   = optional(string)
        claim_name             = string
        claim_value            = string
      })), [])
      external_evaluations = optional(list(object({
        evaluate_url = string
        keys_url     = string
      })), [])
    }))
  }))
  default     = []
  description = <<-EOT
    Reusable Access policies. A policy is the decision - allow, deny, bypass or
    non_identity - and the rule sets it is made on. Applications attach policies
    by name, so the same "Staff on a managed device" policy protects twenty
    applications without being restated.

      - name                           : display name and identity here, matched
                                         lower-cased and trimmed. Renaming destroys
                                         and recreates the policy, and detaches it
                                         from every application referencing it by ID.
      - decision                       : "allow", "deny", "bypass" or "non_identity".
                                           allow        - authenticate, then evaluate the rules
                                           deny         - refuse outright, evaluated before allow
                                           bypass       - no authentication at all. This is the one
                                                          that quietly publishes an application to
                                                          whoever matches the rule, so keep the rule
                                                          narrow and never combine it with everyone.
                                           non_identity - match on posture, IP or service token
                                                          without a login
      - session_duration               : (Optional) overrides the organization default
                                         for applications using this policy, e.g. "8h".
      - isolation_required             : (Optional) force the session through Browser
                                         Isolation.
      - purpose_justification_required : (Optional) make the user type a reason,
                                         recorded in the Access log.
      - purpose_justification_prompt   : (Optional) the wording of that prompt.
      - approval_required              : (Optional) hold the request until an approver
                                         releases it. Needs approval_groups.
      - approval_groups                : (Optional) who may approve, and how many of
                                         them are needed.
      - include / exclude / require    : the same rule shape as access_groups, plus
                                         group_names, which resolves against
                                         var.access_groups.

    Cloudflare evaluates deny before allow, and bypass before either.
  EOT

  validation {
    condition     = alltrue([for p in var.access_policies : trimspace(p.name) != ""])
    error_message = "Each access_policies[*].name must be a non-empty display name."
  }

  validation {
    condition = length(distinct([
      for p in var.access_policies : lower(trimspace(p.name))
    ])) == length(var.access_policies)
    error_message = "access_policies contains duplicate names. Names are compared lower-cased and trimmed, and they are how an application refers to a policy - each policy must be uniquely named."
  }

  validation {
    condition     = alltrue([for p in var.access_policies : contains(["allow", "deny", "bypass", "non_identity"], p.decision)])
    error_message = "Each access_policies[*].decision must be \"allow\", \"deny\", \"bypass\" or \"non_identity\"."
  }

  validation {
    condition = alltrue([
      for p in var.access_policies :
      p.session_duration == null ? true : can(regex("^([0-9]+(ns|us|ms|s|m|h))+$", p.session_duration))
    ])
    error_message = "Each access_policies[*].session_duration must be a Go duration such as \"8h\" or \"2h45m\"."
  }

  validation {
    condition = alltrue([
      for p in var.access_policies :
      try(p.approval_required, false) != true || length(p.approval_groups) > 0
    ])
    error_message = "An access_policies[*] entry sets approval_required without any approval_groups. Nobody could approve the request, so every access attempt would hang."
  }

  validation {
    condition = alltrue(flatten([
      for p in var.access_policies : [
        for g in p.approval_groups : g.approvals_needed > 0
      ]
    ]))
    error_message = "Each access_policies[*].approval_groups[*].approvals_needed must be greater than zero."
  }

  validation {
    condition = alltrue(flatten([
      for p in var.access_policies : [
        for rule in [p.include, p.exclude, p.require] : [
          for code in rule.country_codes : can(regex("^[A-Za-z]{2}$", code))
        ]
        if rule != null
      ]
    ]))
    error_message = "Each access_policies[*] country_codes entry must be a two-letter ISO 3166-1 country code, for example \"GB\"."
  }

  validation {
    condition = alltrue(flatten([
      for p in var.access_policies : [
        for rule in [p.include, p.exclude, p.require] : [
          for cidr in rule.ip_cidrs : can(cidrnetmask(cidr))
        ]
        if rule != null
      ]
    ]))
    error_message = "Each access_policies[*] ip_cidrs entry must be a CIDR range such as 203.0.113.0/24. A bare address needs an explicit /32."
  }

  # A bypass policy that matches everybody removes authentication from every
  # application it is attached to. Cloudflare will happily accept it; the only
  # sign is that the application stops asking anybody to log in.
  validation {
    condition = alltrue([
      for p in var.access_policies :
      p.decision != "bypass" || p.include.everyone != true
    ])
    error_message = "An access_policies[*] entry combines decision = \"bypass\" with include.everyone. That serves the application to the entire internet with no authentication. Name the IP ranges, service tokens or countries the bypass is actually for."
  }
}

variable "access_applications" {
  type = list(object({
    name   = string
    type   = optional(string, "self_hosted")
    domain = optional(string)
    extra_destinations = optional(list(object({
      type        = optional(string, "public")
      uri         = optional(string)
      hostname    = optional(string)
      cidr        = optional(string)
      l4_protocol = optional(string)
      port_range  = optional(string)
      vnet_id     = optional(string)
    })), [])
    policy_names                = optional(list(string), [])
    policy_ids                  = optional(list(string), [])
    allowed_idp_names           = optional(list(string), [])
    allowed_idp_ids             = optional(list(string), [])
    session_duration            = optional(string)
    auto_redirect_to_identity   = optional(bool)
    app_launcher_visible        = optional(bool)
    enable_binding_cookie       = optional(bool)
    http_only_cookie_attribute  = optional(bool)
    same_site_cookie_attribute  = optional(string)
    path_cookie_attribute       = optional(bool)
    custom_deny_message         = optional(string)
    custom_deny_url             = optional(string)
    skip_interstitial           = optional(bool)
    service_auth_401_redirect   = optional(bool)
    options_preflight_bypass    = optional(bool)
    allow_authenticate_via_warp = optional(bool)
    tags                        = optional(list(string), [])
    cors_headers = optional(object({
      allow_all_headers = optional(bool)
      allow_all_methods = optional(bool)
      allow_all_origins = optional(bool)
      allow_credentials = optional(bool)
      allowed_headers   = optional(list(string))
      allowed_methods   = optional(list(string))
      allowed_origins   = optional(list(string))
      max_age           = optional(number)
    }))
  }))
  default     = []
  description = <<-EOT
    The things Access protects. An application is a hostname (or a launcher tile,
    or an SSH target) plus the ordered list of policies evaluated against every
    request for it.

      - name                        : display name and identity here, matched
                                      lower-cased and trimmed.
      - type                        : (Optional) "self_hosted" by default. Also
                                      "ssh", "vnc", "rdp", "warp", "biso",
                                      "bookmark", "app_launcher", "dash_sso",
                                      "infrastructure", "saas", "mcp",
                                      "mcp_portal", "proxy_endpoint".
      - domain                      : the primary hostname, optionally with a path,
                                      e.g. "grafana.example.com". Required for
                                      anything hostname-based, and the zone has to
                                      be on this Cloudflare account with the record
                                      proxied, or Access never sees the request.
      - extra_destinations          : (Optional) anything else the same application
                                      answers on, beyond `domain`. Each entry is:
                                        type        - "public" (default) or "private"
                                        uri         - public only: a hostname, optionally
                                                      with a path, and wildcards allowed
                                        hostname    - private only: an SNI served by the
                                                      origin, reached over WARP
                                        cidr        - private only: an IP range. A single
                                                      address needs /32
                                        l4_protocol - private only: "tcp" or "udp". Omitted,
                                                      both match
                                        port_range  - private only: a port or a range.
                                                      Omitted, all ports match
                                        vnet_id     - private only: restrict to one virtual
                                                      network. Omitted, all match
                                      `domain` is prepended to this list automatically -
                                      see the note at the end.
      - policy_names                : policies from var.access_policies, in
                                      evaluation order. Order is the precedence:
                                      the first match decides.
      - policy_ids                  : (Optional) policies managed elsewhere,
                                      appended after policy_names.
      - allowed_idp_names           : (Optional) restrict the login page to these
                                      providers from var.identity_providers. Empty
                                      offers every provider on the account. Read
                                      the caveat below before using it.
      - allowed_idp_ids             : (Optional) the same, for providers managed
                                      elsewhere.
      - session_duration            : (Optional) overrides the organization default.
      - auto_redirect_to_identity   : (Optional) skip the provider chooser. Only
                                      sensible with exactly one allowed provider.
      - app_launcher_visible        : (Optional) show a tile in the Access launcher.
      - enable_binding_cookie       : (Optional) bind the session cookie to the
                                      client, which blocks cookie replay from
                                      another device.
      - http_only_cookie_attribute  : (Optional) keep the session cookie away from
                                      JavaScript. Leave on unless a front end
                                      genuinely has to read it.
      - same_site_cookie_attribute  : (Optional) "none", "lax" or "strict".
      - path_cookie_attribute       : (Optional) scope the cookie to the app's path.
      - custom_deny_message         : (Optional) text shown to somebody refused.
      - custom_deny_url             : (Optional) where to send them instead.
      - skip_interstitial           : (Optional) drop the "you are being redirected"
                                      page. Useful for APIs, confusing for people.
      - service_auth_401_redirect   : (Optional) return 401 rather than an HTML
                                      login page. Turn it on for anything a machine
                                      calls, so a failed call fails visibly.
      - options_preflight_bypass    : (Optional) let CORS preflights through unauthenticated.
      - allow_authenticate_via_warp : (Optional) accept WARP device identity in place
                                      of a browser login for this application.
      - tags                        : (Optional) Access tags for grouping in the dashboard.
      - cors_headers                : (Optional) CORS handling for a browser-called API.

    An application with no policies is reachable by nobody, which is a safe
    default but rarely the intent, so the plan refuses it.

    allowed_idp_names cannot name a provider that does not exist yet. Cloudflare
    models allowed_idps as a set, and a set holding an ID that is only known
    after apply is unknown in its entirety, which the provider rejects at plan
    with "Received unknown value, however the target type cannot handle unknown
    values". So an identity provider and an application restricted to it cannot
    be created in one run. Either apply the provider first and the application
    after, or express the restriction in a policy instead, with
    login_method_names - policy rules are typed in a way that copes with an ID
    that is not known yet, and they are enforced rather than merely displayed.

    `domain` is folded into the destinations list this module sends, ahead of
    anything in extra_destinations. That is not a convenience. Cloudflare's
    `destinations` field replaced the deprecated `self_hosted_domains` and is the
    COMPLETE set of what Access secures for an application - the API's own words
    are "if destinations are provided, then self_hosted_domains will be ignored".
    `domain` is described only as "the primary hostname and path secured by
    Access ... displayed if the app is visible in the App Launcher", so sending a
    destinations list that omits it leaves the application's own hostname out of
    the set Access protects, while the dashboard still shows it as the app's
    domain. The failure mode is an application that looks protected and is not,
    which is the one failure mode worth engineering against here.
  EOT

  validation {
    condition     = alltrue([for a in var.access_applications : trimspace(a.name) != ""])
    error_message = "Each access_applications[*].name must be a non-empty display name."
  }

  validation {
    condition = length(distinct([
      for a in var.access_applications : lower(trimspace(a.name))
    ])) == length(var.access_applications)
    error_message = "access_applications contains duplicate names. Names are compared lower-cased and trimmed - each application must be uniquely named."
  }

  # Inlined rather than held in a local: variable validation cannot reference
  # locals, and TFLint's recommended preset deletes a local nothing else reads.
  validation {
    condition = alltrue([
      for a in var.access_applications : contains([
        "self_hosted", "saas", "ssh", "vnc", "app_launcher", "warp", "biso",
        "bookmark", "dash_sso", "infrastructure", "rdp", "mcp", "mcp_portal",
        "proxy_endpoint",
      ], a.type)
    ])
    error_message = "Each access_applications[*].type must be one of self_hosted, saas, ssh, vnc, app_launcher, warp, biso, bookmark, dash_sso, infrastructure, rdp, mcp, mcp_portal, proxy_endpoint."
  }

  validation {
    condition = alltrue([
      for a in var.access_applications :
      contains(["app_launcher", "warp", "biso", "dash_sso", "infrastructure"], a.type) || trimspace(coalesce(a.domain, " ")) != ""
    ])
    error_message = "Each access_applications[*] entry of a hostname-based type must set domain. Only app_launcher, warp, biso, dash_sso and infrastructure applications have no hostname of their own."
  }

  validation {
    condition = alltrue([
      for a in var.access_applications : length(a.policy_names) + length(a.policy_ids) > 0
    ])
    error_message = "Each access_applications[*] entry must attach at least one policy through policy_names or policy_ids. An application with no policies is protected from everybody, including the people it was created for."
  }

  validation {
    condition = alltrue(flatten([
      for a in var.access_applications : [
        for d in a.extra_destinations : contains(["public", "private"], d.type)
      ]
    ]))
    error_message = "Each access_applications[*].extra_destinations[*].type must be \"public\" or \"private\"."
  }

  # A public destination with no uri is silently ignored by Cloudflare, so the
  # hostname somebody meant to protect is simply not protected.
  validation {
    condition = alltrue(flatten([
      for a in var.access_applications : [
        for d in a.extra_destinations : trimspace(coalesce(d.uri, " ")) != ""
        if d.type == "public"
      ]
    ]))
    error_message = "Each public access_applications[*].extra_destinations[*] must set uri - the hostname, optionally with a path. Use type = \"private\" for something reached over WARP by IP or SNI."
  }

  validation {
    condition = alltrue(flatten([
      for a in var.access_applications : [
        for d in a.extra_destinations :
        d.hostname == null && d.cidr == null && d.l4_protocol == null && d.port_range == null && d.vnet_id == null
        if d.type == "public"
      ]
    ]))
    error_message = "A public access_applications[*].extra_destinations[*] entry sets hostname, cidr, l4_protocol, port_range or vnet_id. Those describe a private destination reached over WARP; a public one takes uri and nothing else."
  }

  validation {
    condition = alltrue(flatten([
      for a in var.access_applications : [
        for d in a.extra_destinations : d.uri == null && (d.hostname != null || d.cidr != null)
        if d.type == "private"
      ]
    ]))
    error_message = "Each private access_applications[*].extra_destinations[*] must set hostname or cidr, and must not set uri. A private destination is matched by SNI or by IP range over WARP, not by URL."
  }

  validation {
    condition = alltrue(flatten([
      for a in var.access_applications : [
        for d in a.extra_destinations : can(cidrnetmask(d.cidr))
        if d.cidr != null
      ]
    ]))
    error_message = "Each access_applications[*].extra_destinations[*].cidr must be a CIDR range such as 10.0.0.0/24. A single address needs an explicit /32."
  }

  validation {
    condition = alltrue(flatten([
      for a in var.access_applications : [
        for d in a.extra_destinations : contains(["tcp", "udp"], d.l4_protocol)
        if d.l4_protocol != null
      ]
    ]))
    error_message = "access_applications[*].extra_destinations[*].l4_protocol must be \"tcp\" or \"udp\" when set. Leave it unset to match both."
  }

  # Cloudflare takes the destinations list as the complete set of what Access
  # secures, so a duplicate is not additive - it is a sign the primary domain has
  # been restated, or that two entries were meant to differ and do not.
  validation {
    condition = alltrue([
      for a in var.access_applications :
      length(distinct([for d in a.extra_destinations : lower(trimspace(coalesce(d.uri, d.hostname, d.cidr, "")))])) == length(a.extra_destinations)
    ])
    error_message = "An access_applications[*].extra_destinations list names the same destination twice. `domain` is added to the list automatically, so it does not need restating there either."
  }

  validation {
    condition = alltrue([
      for a in var.access_applications :
      a.session_duration == null ? true : can(regex("^([0-9]+(ns|us|ms|s|m|h))+$", a.session_duration))
    ])
    error_message = "Each access_applications[*].session_duration must be a Go duration such as \"24h\"."
  }

  validation {
    condition = alltrue([
      for a in var.access_applications :
      a.same_site_cookie_attribute == null ? true : contains(["none", "lax", "strict"], a.same_site_cookie_attribute)
    ])
    error_message = "access_applications[*].same_site_cookie_attribute must be \"none\", \"lax\" or \"strict\" when set."
  }

  validation {
    condition = alltrue([
      for a in var.access_applications :
      length(distinct(concat(a.policy_names, a.policy_ids))) == length(a.policy_names) + length(a.policy_ids)
    ])
    error_message = "An access_applications[*] entry attaches the same policy twice. Cloudflare orders policies by their position in the list, so a duplicate is either a copy-paste or a precedence mistake."
  }
}
