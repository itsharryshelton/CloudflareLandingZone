# The type of an Access group, an Access policy and the rule sets inside them.
#
# This exists because Terraform has no type aliases. A group has three rule
# sets and so does a policy, all six the same object, and declared on the
# parent's variables that object is written out six times and kept in step by
# hand. Here it is written once: the parent flattens the six positions into one
# map and passes it through var.rule_sets.
#
# Nothing in here creates anything. Each output is its variable, after
# Terraform has converted it to the declared type, filled in the defaults and
# run the validation rules - which is all a typed variable on the parent would
# have done.

variable "access_groups" {
  type = list(object({
    name       = string
    is_default = optional(bool)
    # Presence and kind only, so a group without an include is still refused
    # here. The contents arrive through var.rule_sets.
    include = object({})
    exclude = optional(object({}))
    require = optional(object({}))
  }))
  description = "The parent module's var.access_groups, which documents every field. The rule sets are checked for presence only; their contents are typed by var.rule_sets."

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
    # Presence and kind only, as for access_groups. `everyone` is declared
    # because the bypass check below reads it alongside `decision`, which
    # var.rule_sets cannot see.
    include = object({
      everyone = optional(bool, false)
    })
    exclude = optional(object({}))
    require = optional(object({}))
  }))
  description = "The parent module's var.access_policies, which documents every field. The rule sets are checked for presence only; their contents are typed by var.rule_sets."

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

variable "rule_sets" {
  type = map(object({
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
  description = <<-EOT
    Every include, exclude and require of every group and policy, keyed
    "access_groups.<name>.include", "access_policies.<name>.require" and so on,
    with <name> lower-cased and trimmed. The parent module's var.access_groups
    says what each attribute matches.

    This is the one declaration of the rule set type. Add an attribute here and
    all six positions accept it.
  EOT

  validation {
    condition = alltrue([
      for path, rule in var.rule_sets : length(rule.group_names) == 0
      if startswith(path, "access_groups.")
    ])
    error_message = "access_groups[*] rules must not use group_names. A group referencing another group created by this module is a Terraform dependency cycle, not a configuration error Cloudflare would report. Use group_ids for a group managed outside this module, or merge the two rule sets."
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.rule_sets : [
        for code in rule.country_codes : can(regex("^[A-Za-z]{2}$", code))
      ]
    ]))
    error_message = "Each country_codes entry must be a two-letter ISO 3166-1 country code, for example \"GB\". Not one: ${join("; ", flatten([for path, rule in var.rule_sets : [for code in rule.country_codes : "${path}.country_codes -> \"${code}\"" if !can(regex("^[A-Za-z]{2}$", code))]]))}."
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.rule_sets : [
        for cidr in rule.ip_cidrs : can(cidrnetmask(cidr))
      ]
    ]))
    error_message = "Each ip_cidrs entry must be a CIDR range such as 203.0.113.0/24. A bare address needs an explicit /32. Not one: ${join("; ", flatten([for path, rule in var.rule_sets : [for cidr in rule.ip_cidrs : "${path}.ip_cidrs -> \"${cidr}\"" if !can(cidrnetmask(cidr))]]))}."
  }
}
