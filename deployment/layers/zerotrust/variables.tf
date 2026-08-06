# Layer zerotrust - inputs.
#
# Two config sources feed it:
#   accounts/<account>/account.tfvars     the account ID
#   accounts/<account>/zerotrust.tfvars   everything below except the secrets

variable "cloudflare_account_id" {
  type        = string
  description = <<-EOT
    Cloudflare Account ID this layer run targets. Supplied from
    accounts/<account>/account.tfvars, or overridden with
    TF_VAR_cloudflare_account_id.
  EOT

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zero_trust_team_name" {
  type        = string
  default     = null
  description = <<-EOT
    The account's Zero Trust team name - the "acme" in
    acme.cloudflareaccess.com. It is the address of every Access login page and
    the value WARP clients enrol against.

    Leave it null and the layer adopts whatever team name the account already
    has, which is the right answer for an account somebody set up in the
    dashboard: Terraform takes over the organization without renaming it.

    Set it and the layer asserts the account's team name matches. Changing it on
    an account that already has a different one is refused unless
    allow_team_name_change is set, because a rename breaks every Access URL,
    every enrolled device and every bookmark at once, and releases the old name
    for anybody else to claim.

    An account that has never enabled Zero Trust has no team name at all, and
    Terraform cannot pick one for it - the provider updates the organization
    rather than creating it. The plan says so, and says what to do about it.
  EOT

  validation {
    condition     = var.zero_trust_team_name == null || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", coalesce(var.zero_trust_team_name, "x")))
    error_message = "zero_trust_team_name must be 1-63 characters of lower-case letters, digits and hyphens, not starting or ending with a hyphen. It becomes <name>.cloudflareaccess.com."
  }
}

variable "zero_trust_organization_name" {
  type        = string
  default     = null
  description = "Display name for the Zero Trust organization, shown on the Access login page. Defaults to the team name."
}

variable "identity_providers" {
  description = <<-EOT
    Login methods Access offers, keyed by a logical key. Rules and applications
    reference a provider by that key.

    The key is a handle and renaming it moves nothing in Cloudflare. The `name`
    is identity: changing it destroys and recreates the provider, which signs
    everybody out.

    - `name`        - Display name on the login page.
    - `type`        - "azureAD" for Microsoft Entra ID, "onetimepin" for the built-in
                      email PIN, or one of saml, oidc, google, google-apps, okta,
                      onelogin, pingone, centrify, github, facebook, linkedin,
                      yandex, cloudflare.
    - `config`      - Provider settings. For Entra ID the three that matter are
                      `client_id` and `directory_id` from the app registration, plus
                      `support_groups = true` if any rule is going to match on an
                      Entra group. `conditional_access_enabled = true` additionally
                      pulls through Conditional Access authentication contexts.
                      There is NO client_secret field here on purpose - see
                      var.identity_provider_secrets.
    - `scim_config` - (Optional) SCIM provisioning. `user_deprovision` and
                      `seat_deprovision` are the point of it: somebody disabled in
                      Entra loses Cloudflare access without a Terraform run.

    Deleting an entry removes the login method, and anybody who could only
    authenticate that way loses access on the next apply.
  EOT
  type = map(object({
    name = string
    type = string
    config = optional(object({
      client_id                  = optional(string)
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
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.identity_providers) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "identity_providers keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for provider in var.identity_providers : lower(trimspace(provider.name))
    ])) == length(var.identity_providers)
    error_message = "Two identity_providers entries share a name. The name is the provider's identity in Cloudflare, so each must be uniquely named."
  }
}

variable "identity_provider_secrets" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = <<-EOT
    OAuth client secrets, keyed by the same key as var.identity_providers. The
    Entra ID app registration's client secret goes here, and nowhere else.

    THIS VARIABLE IS NEVER SET FROM A FILE. It arrives from the pipeline as
    TF_VAR_identity_provider_secrets, read from the apply environment's secrets:

      TF_VAR_identity_provider_secrets={"entra_id":"<the secret>"}

    Two things follow from that, and neither is optional reading.

    A secret written into a .tfvars is committed the moment somebody runs
    `git add .`, and .gitignore will not save you: accounts/*/*.tfvars is
    explicitly un-ignored so account trees can be committed. CI greps committed
    tfvars for credential-shaped strings, but that is a backstop, not a control.

    The value reaches Terraform state in plain text regardless of how it is
    supplied, because Cloudflare stores it and Terraform records what it sent.
    State is therefore a credential store: it lives in R2 behind keys held in
    GitHub Environments, it is never committed, and a plan file is as sensitive
    as it is. Rotating the Entra secret means rotating it in Entra, updating the
    environment secret and re-applying - not editing a file.
  EOT
}

variable "service_tokens" {
  description = <<-EOT
    Machine credentials, keyed by a logical key. A service token is a client ID
    and secret pair a caller sends in CF-Access-Client-Id and
    CF-Access-Client-Secret headers to reach an application without a browser.

    - `name`     - Display name, and the token's identity in Cloudflare. Renaming
                   issues a new secret and breaks every caller holding the old one.
    - `duration` - (Optional) Validity, for example "8760h" for a year. Defaults to
                   var.default_service_token_duration.

    The generated secret is shown once by Cloudflare and is not an output of
    this layer. Read it from state or the dashboard when the token is first
    created, hand it to the consumer through a secret store, and rotate it by
    recreating the token.
  EOT
  type = map(object({
    name     = string
    duration = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.service_tokens) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "service_tokens keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for token in var.service_tokens : lower(trimspace(token.name))
    ])) == length(var.service_tokens)
    error_message = "Two service_tokens entries share a name. The name is the token's identity in Cloudflare, so each must be uniquely named."
  }
}

variable "access_groups" {
  description = <<-EOT
    Reusable audiences, keyed by a logical key. A group answers "who counts as an
    administrator" once, and every policy that needs the same answer references
    it instead of restating it.

    The key is a handle. The `name` is identity: renaming it destroys and
    recreates the group.

    - `name`       - Display name in the Zero Trust dashboard.
    - `is_default` - (Optional) Attach this group to every Access application
                     created afterwards. Off unless you mean it.
    - `include`    - Match any one of these and the group matches. Required.
    - `exclude`    - (Optional) Match any one of these and the group does not match,
                     whatever include said. Exclude beats include.
    - `require`    - (Optional) Conditions that must hold as well.

    A rule set is an OR across everything named in it. Leave a field out and it
    plays no part.

      everyone                - any identity that authenticated successfully
      emails                  - exact addresses
      email_domains           - everybody at a domain, for example "example.com"
      email_list_ids          - a Cloudflare list of addresses, by ID
      ip_cidrs                - source IP ranges, in CIDR form
      ip_list_ids             - a Cloudflare list of IPs, by ID
      country_codes           - two-letter ISO country codes
      group_keys              - keys from var.access_groups
      group_ids               - Access groups managed outside this layer, by ID
      service_token_keys      - keys from var.service_tokens
      service_token_ids       - service tokens managed elsewhere, by ID
      any_valid_service_token - any service token on the account
      certificate             - a valid client certificate (mTLS)
      common_names            - a client certificate carrying this CN
      auth_methods            - AMR values from the identity provider, "mfa" being the one
                                worth knowing: it means the provider asserted the user
                                completed multi-factor, not that Cloudflare prompted for it
      device_posture_ids      - WARP device posture rule IDs
      login_method_keys       - restrict to these providers, by key from
                                var.identity_providers
      login_method_ids        - the same, for a provider managed elsewhere
      entra_groups            - a Microsoft Entra ID group's object ID. Needs
                                support_groups on the provider, or Entra never sends
                                the membership and the rule silently matches nobody
      entra_auth_contexts     - an Entra Conditional Access authentication context
      saml_attributes         - a SAML attribute name and value
      oidc_claims             - an OIDC claim name and value
      external_evaluations    - delegate the decision to an external service

    Anything taking an identity provider accepts either identity_provider_key,
    resolved against var.identity_providers, or identity_provider_id for one
    managed elsewhere. Exactly one of the two.

    group_keys is rejected here. A group nesting another group this layer also
    creates is a Terraform dependency cycle rather than a configuration error,
    and the message would be unreadable. Nest an externally managed group with
    group_ids, or merge the two rule sets.
  EOT
  type = map(object({
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
      group_keys              = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_keys      = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_keys       = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        group_id              = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        id                    = string
        ac_id                 = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        attribute_name        = string
        attribute_value       = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        claim_name            = string
        claim_value           = string
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
      group_keys              = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_keys      = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_keys       = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        group_id              = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        id                    = string
        ac_id                 = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        attribute_name        = string
        attribute_value       = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        claim_name            = string
        claim_value           = string
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
      group_keys              = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_keys      = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_keys       = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        group_id              = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        id                    = string
        ac_id                 = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        attribute_name        = string
        attribute_value       = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        claim_name            = string
        claim_value           = string
      })), [])
      external_evaluations = optional(list(object({
        evaluate_url = string
        keys_url     = string
      })), [])
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.access_groups) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "access_groups keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for group in var.access_groups : lower(trimspace(group.name))
    ])) == length(var.access_groups)
    error_message = "Two access_groups entries share a name. The name is the group's identity in Cloudflare, so each must be uniquely named."
  }

  validation {
    condition = alltrue(flatten([
      for group in var.access_groups : [
        for rule in [group.include, group.exclude, group.require] : length(rule.group_keys) == 0
        if rule != null
      ]
    ]))
    error_message = "access_groups[*] rules must not use group_keys. A group referencing another group created by this layer is a Terraform dependency cycle, not something Cloudflare would report. Use group_ids for a group managed elsewhere, or merge the two rule sets."
  }
}

variable "access_policies" {
  description = <<-EOT
    Reusable Access policies, keyed by a logical key. A policy is a decision plus
    the rules it rests on; applications attach policies by key, so the same
    "Platform engineers on a managed device" policy can protect twenty
    applications without being restated.

    The key is a handle. The `name` is identity: renaming destroys and recreates
    the policy.

    - `name`                           - Display name in the dashboard.
    - `decision`                       - "allow", "deny", "bypass" or "non_identity".
                                           allow        - authenticate, then evaluate the rules
                                           deny         - refuse, evaluated before allow
                                           bypass       - no authentication at all. Restricted by
                                                          default; see var.restricted_policy_decisions
                                           non_identity - match on posture, IP or a service token
                                                          with no login, which is what a machine
                                                          caller needs
    - `session_duration`               - (Optional) Overrides the organization default.
    - `isolation_required`             - (Optional) Force the session through Browser Isolation.
    - `purpose_justification_required` - (Optional) Make the user type a reason, recorded
                                         in the Access log.
    - `purpose_justification_prompt`   - (Optional) The wording of that prompt.
    - `approval_required`              - (Optional) Hold the request until somebody approves.
    - `approval_groups`                - (Optional) Who may approve, and how many are needed.
    - `include` / `exclude` / `require`

    A rule set is an OR across everything named in it. Leave a field out and it
    plays no part.

      everyone                - any identity that authenticated successfully
      emails                  - exact addresses
      email_domains           - everybody at a domain, for example "example.com"
      email_list_ids          - a Cloudflare list of addresses, by ID
      ip_cidrs                - source IP ranges, in CIDR form
      ip_list_ids             - a Cloudflare list of IPs, by ID
      country_codes           - two-letter ISO country codes
      group_keys              - keys from var.access_groups
      group_ids               - Access groups managed outside this layer, by ID
      service_token_keys      - keys from var.service_tokens
      service_token_ids       - service tokens managed elsewhere, by ID
      any_valid_service_token - any service token on the account
      certificate             - a valid client certificate (mTLS)
      common_names            - a client certificate carrying this CN
      auth_methods            - AMR values from the identity provider, "mfa" being the one
                                worth knowing: it means the provider asserted the user
                                completed multi-factor, not that Cloudflare prompted for it
      device_posture_ids      - WARP device posture rule IDs
      login_method_keys       - restrict to these providers, by key from
                                var.identity_providers
      login_method_ids        - the same, for a provider managed elsewhere
      entra_groups            - a Microsoft Entra ID group's object ID. Needs
                                support_groups on the provider, or Entra never sends
                                the membership and the rule silently matches nobody
      entra_auth_contexts     - an Entra Conditional Access authentication context
      saml_attributes         - a SAML attribute name and value
      oidc_claims             - an OIDC claim name and value
      external_evaluations    - delegate the decision to an external service

    Anything taking an identity provider accepts either identity_provider_key,
    resolved against var.identity_providers, or identity_provider_id for one
    managed elsewhere. Exactly one of the two.
  EOT
  type = map(object({
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
      group_keys              = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_keys      = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_keys       = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        group_id              = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        id                    = string
        ac_id                 = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        attribute_name        = string
        attribute_value       = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        claim_name            = string
        claim_value           = string
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
      group_keys              = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_keys      = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_keys       = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        group_id              = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        id                    = string
        ac_id                 = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        attribute_name        = string
        attribute_value       = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        claim_name            = string
        claim_value           = string
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
      group_keys              = optional(list(string), [])
      group_ids               = optional(list(string), [])
      service_token_keys      = optional(list(string), [])
      service_token_ids       = optional(list(string), [])
      any_valid_service_token = optional(bool, false)
      certificate             = optional(bool, false)
      common_names            = optional(list(string), [])
      auth_methods            = optional(list(string), [])
      device_posture_ids      = optional(list(string), [])
      login_method_keys       = optional(list(string), [])
      login_method_ids        = optional(list(string), [])
      entra_groups = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        group_id              = string
      })), [])
      entra_auth_contexts = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        id                    = string
        ac_id                 = string
      })), [])
      saml_attributes = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        attribute_name        = string
        attribute_value       = string
      })), [])
      oidc_claims = optional(list(object({
        identity_provider_key = optional(string)
        identity_provider_id  = optional(string)
        claim_name            = string
        claim_value           = string
      })), [])
      external_evaluations = optional(list(object({
        evaluate_url = string
        keys_url     = string
      })), [])
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.access_policies) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "access_policies keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for policy in var.access_policies : lower(trimspace(policy.name))
    ])) == length(var.access_policies)
    error_message = "Two access_policies entries share a name. The name is the policy's identity in Cloudflare, so each must be uniquely named."
  }

  validation {
    condition     = alltrue([for policy in var.access_policies : contains(["allow", "deny", "bypass", "non_identity"], policy.decision)])
    error_message = "Each access_policies[*].decision must be \"allow\", \"deny\", \"bypass\" or \"non_identity\"."
  }
}

variable "access_applications" {
  description = <<-EOT
    The things Access protects, keyed by a logical key. An application is a
    hostname plus the ordered list of policies evaluated for every request to it.

    - `name`                        - Display name in the dashboard and the app launcher.
    - `type`                        - (Optional) "self_hosted" by default. Also ssh, vnc,
                                      rdp, warp, biso, bookmark, app_launcher, dash_sso,
                                      infrastructure, saas, mcp, mcp_portal, proxy_endpoint.
    - `domain`                      - The hostname Access sits in front of, for example
                                      "grafana.example.com". The DNS record for it must be
                                      proxied, or the request never reaches Cloudflare and
                                      Access never sees it. Managed in the zones layer, not here.
    - `extra_destinations`          - (Optional) Anything else the same application answers
                                      on, beyond `domain`. Each entry is:
                                        `type`        - "public" (default) or "private"
                                        `uri`         - public only: hostname, optionally with
                                                        a path, wildcards allowed
                                        `hostname`    - private only: an SNI served by the
                                                        origin, reached over WARP
                                        `cidr`        - private only: an IP range. A single
                                                        address needs /32
                                        `l4_protocol` - private only: "tcp" or "udp"
                                        `port_range`  - private only: a port or a range
                                        `vnet_id`     - private only: one virtual network
                                      `domain` is added to the list automatically, so do not
                                      restate it here. See the note at the end.
    - `policy_keys`                 - Keys from var.access_policies, IN EVALUATION ORDER.
                                      The first match decides, so put deny policies first.
    - `policy_ids`                  - (Optional) Policies managed elsewhere, appended after.
    - `allowed_idp_keys`            - (Optional) Restrict the login page to these providers.
                                      Empty offers every provider on the account. This cannot
                                      name a provider created in the same run - see the note
                                      at the end.
    - `allowed_idp_ids`             - (Optional) The same, by ID.
    - `session_duration`            - (Optional) Overrides the organization default.
    - `auto_redirect_to_identity`   - (Optional) Skip the provider chooser. Only sensible with
                                      exactly one allowed provider.
    - `app_launcher_visible`        - (Optional) Show a tile in the Access launcher.
    - `enable_binding_cookie`       - (Optional) Bind the session cookie to the client, which
                                      stops it being replayed from another machine.
    - `http_only_cookie_attribute`  - (Optional) Keep the session cookie away from JavaScript.
                                      Leave it on unless a front end genuinely has to read it.
    - `same_site_cookie_attribute`  - (Optional) "none", "lax" or "strict".
    - `path_cookie_attribute`       - (Optional) Scope the cookie to the application's path.
    - `custom_deny_message`         - (Optional) What somebody refused is told.
    - `custom_deny_url`             - (Optional) Where they are sent instead.
    - `skip_interstitial`           - (Optional) Drop the redirect notice. Useful for APIs.
    - `service_auth_401_redirect`   - (Optional) Answer 401 rather than serving a login page.
                                      Turn it on for anything a machine calls, so a failure
                                      is a failure rather than a page of HTML.
    - `options_preflight_bypass`    - (Optional) Let CORS preflights through unauthenticated.
    - `allow_authenticate_via_warp` - (Optional) Accept WARP device identity instead of a
                                      browser login.
    - `tags`                        - (Optional) Access tags, for grouping in the dashboard.
    - `cors_headers`                - (Optional) CORS handling for a browser-called API.

    allowed_idp_keys cannot name a provider that does not exist yet. Cloudflare
    models the field as a set, and a set holding an ID that is only known after
    apply is unknown in its entirety, which the provider refuses at plan time.
    Apply the provider first and the application after, or express the
    restriction as login_method_keys in a policy, which is enforced rather than
    merely displayed and copes with an ID that is not known yet.

    Cloudflare's `destinations` field replaced the deprecated
    `self_hosted_domains`, which was supported only until 21 November 2025, and
    it is the COMPLETE set of what Access secures for an application - the API's
    own words are "if destinations are provided, then self_hosted_domains will be
    ignored". `domain` is only the primary hostname shown in the App Launcher, so
    the layer prepends it to the list rather than leaving it out. An application
    whose destinations omitted its own hostname would look protected in the
    dashboard and would not be.
  EOT
  type = map(object({
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
    policy_keys                 = optional(list(string), [])
    policy_ids                  = optional(list(string), [])
    allowed_idp_keys            = optional(list(string), [])
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
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.access_applications) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "access_applications keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for application in var.access_applications : lower(trimspace(application.name))
    ])) == length(var.access_applications)
    error_message = "Two access_applications entries share a name. Each application must be uniquely named."
  }

  validation {
    condition = alltrue([
      for application in var.access_applications : length(application.policy_keys) + length(application.policy_ids) > 0
    ])
    error_message = "Each access_applications entry must attach at least one policy through policy_keys or policy_ids. An application with no policies is protected from everybody, including the people it was created for."
  }
}

# Platform defaults (defaults.auto.tfvars)
variable "default_session_duration" {
  type        = string
  default     = "24h"
  description = <<-EOT
    How long an Access session lasts before the user authenticates again, for any
    application and policy that sets none of its own. Applied to the Zero Trust
    organization.

    A long session is convenient and is also how a laptop left in a taxi stays
    signed in. Shorten it for an account whose applications are sensitive rather
    than lengthening it for one whose users complain.
  EOT

  validation {
    condition     = can(regex("^([0-9]+(ns|us|ms|s|m|h))+$", var.default_session_duration))
    error_message = "default_session_duration must be a Go duration such as \"24h\" or \"2h45m\"."
  }
}

variable "default_warp_auth_session_duration" {
  type        = string
  default     = "24h"
  description = "How long a WARP authentication session lasts before the device re-authenticates. Same trade-off as default_session_duration, applied to enrolled devices."

  validation {
    condition     = can(regex("^([0-9]+(ns|us|ms|s|m|h))+$", var.default_warp_auth_session_duration))
    error_message = "default_warp_auth_session_duration must be a Go duration such as \"24h\"."
  }
}

variable "default_service_token_duration" {
  type        = string
  default     = "8760h"
  description = <<-EOT
    Validity given to a service token that names no duration of its own. A year
    by default, which is short enough to force a rotation into somebody's plan
    and long enough not to break a system nobody is watching.

    Cloudflare also accepts "forever". A credential nobody is ever obliged to
    rotate is one that outlives the person who created it, so setting that here
    is a decision for a pull request rather than a convenience.
  EOT

  validation {
    condition     = var.default_service_token_duration == "forever" || can(regex("^([0-9]+(ns|us|ms|s|m|h))+$", var.default_service_token_duration))
    error_message = "default_service_token_duration must be a Go duration such as \"8760h\", or the literal \"forever\"."
  }
}

variable "user_seat_expiration_inactive_time" {
  type        = string
  default     = "730h"
  description = "How long a Zero Trust seat survives with no login before Cloudflare releases it. Cloudflare's minimum is 730h, about a month. It is the mechanism that stops a leaver holding a seat, and a licence, indefinitely."

  validation {
    condition     = can(regex("^([0-9]+(ns|us|ms|s|m|h))+$", var.user_seat_expiration_inactive_time))
    error_message = "user_seat_expiration_inactive_time must be a Go duration such as \"730h\". Cloudflare's minimum is 730h."
  }
}

variable "lock_dashboard_to_read_only" {
  type        = bool
  default     = false
  description = <<-EOT
    Lock every Zero Trust setting in the Cloudflare dashboard to read-only, for
    everybody, whatever role they hold.

    Turning it on is what makes this repository the only route to an Access
    change: a dashboard edit stops being possible rather than merely being
    against policy, and drift stops appearing between applies. It is off by
    default because an account still being built needs the dashboard, and
    because switching it on while somebody is mid-migration is unkind.

    Turn it on once the account is steady. Lifting it is a one-line change here
    with a reason recorded in ui_read_only_toggle_reason.
  EOT
}

variable "ui_read_only_toggle_reason" {
  type        = string
  default     = null
  description = "The reason recorded by Cloudflare when lock_dashboard_to_read_only is lifted. Set it in the same pull request that lifts the lock, so the audit trail says why."
}

variable "auto_redirect_to_identity" {
  type        = bool
  default     = false
  description = "Skip the identity provider chooser and send users straight to the only provider that makes sense. Leave it off while more than one login method is in play, or people who need the other one cannot reach it."
}

variable "allow_authenticate_via_warp" {
  type        = bool
  default     = false
  description = "Let a WARP-enrolled device satisfy authentication for any application, without a browser login. Convenient, and it makes device enrolment the thing protecting the application, so turn it on only where enrolment is itself controlled."
}

variable "login_design" {
  type = object({
    background_color = optional(string)
    footer_text      = optional(string)
    header_text      = optional(string)
    logo_path        = optional(string)
    text_color       = optional(string)
  })
  default     = null
  description = <<-EOT
    Branding for the Access login page: colours, header and footer text, and a
    logo URL. Cosmetic, and worth setting - a login page that looks like the
    organisation is one users are less likely to abandon, and easier to tell
    apart from a phishing page.
  EOT
}

variable "restricted_policy_decisions" {
  type        = list(string)
  default     = ["bypass"]
  description = <<-EOT
    Policy decisions this layer refuses to create. The plan fails naming the
    policy and the decision.

    "bypass" is restricted by default because it removes authentication
    altogether from every application it is attached to. That is occasionally
    the right answer - a health check endpoint, an ACME challenge path - and it
    is never something that should arrive as a one-word edit to an account tree.
    Allowing it means removing it from this list on a pull request that says why.

    Emptying the list disables the check.
  EOT
}

variable "allowed_email_domains" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Email domains an Access rule may admit, for example ["example.com"]. Matched
    case-insensitively against email_domains entries and against the part after
    the "@" in emails entries. Empty, the default, allows any domain.

    Set it wherever Access should only ever admit staff of one organisation. It
    turns a mistyped domain, or a personal address added in a hurry, into a
    failed plan rather than a door nobody notices is open.
  EOT

  validation {
    condition     = alltrue([for domain in var.allowed_email_domains : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", lower(trimspace(domain))))])
    error_message = "Each allowed_email_domains entry must be a bare domain such as example.com - no \"@\", no scheme, no path."
  }
}

variable "allow_team_name_change" {
  type        = bool
  default     = false
  description = <<-EOT
    Permit zero_trust_team_name to differ from the team name the account already
    has, which renames the team domain.

    Off by default because a rename is not a rename to anybody using the
    account. Every Access application URL changes, every enrolled WARP device
    has to be re-enrolled, every bookmark and every documented link breaks, and
    the old name is released for anybody else to register. Doing it deliberately
    means setting this true, applying, and setting it back.
  EOT
}
