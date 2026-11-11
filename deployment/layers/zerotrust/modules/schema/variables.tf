# The type of an Access group, an Access policy and the rule sets inside them,
# as an account tree writes them.
#
# This exists because Terraform has no type aliases. A group has three rule
# sets and so does a policy, all six the same object, and declared on the
# layer's variables that object is written out six times and kept in step by
# hand. Here it is written once: the layer flattens the six positions into one
# map and passes it through var.rule_sets.
#
# Nothing in here creates anything. Each output is its variable, after
# Terraform has converted it to the declared type, filled in the defaults and
# run the validation rules - which is all a typed variable on the layer would
# have done.
#
# modules/zerotrust has a schema module of its own. The two differ in the
# attributes that carry a reference: keys here, Cloudflare names there.

variable "access_groups" {
  type = map(object({
    name       = string
    is_default = optional(bool)
    # Presence and kind only, so a group without an include is still refused
    # here. The contents arrive through var.rule_sets.
    include = object({})
    exclude = optional(object({}))
    require = optional(object({}))
  }))
  description = "The layer's var.access_groups, which documents every field. The rule sets are checked for presence only; their contents are typed by var.rule_sets."

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
}

variable "access_policies" {
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
    # Presence and kind only, as for access_groups.
    include = object({})
    exclude = optional(object({}))
    require = optional(object({}))
  }))
  description = "The layer's var.access_policies, which documents every field. The rule sets are checked for presence only; their contents are typed by var.rule_sets."

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

variable "rule_sets" {
  type = map(object({
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
  description = <<-EOT
    Every include, exclude and require of every group and policy, keyed
    "access_groups.<key>.include", "access_policies.<key>.require" and so on.
    The layer's var.access_groups says what each attribute matches.

    This is the one declaration of the rule set type. Add an attribute here and
    all six positions accept it.
  EOT

  validation {
    condition = alltrue([
      for path, rule in var.rule_sets : length(rule.group_keys) == 0
      if startswith(path, "access_groups.")
    ])
    error_message = "access_groups[*] rules must not use group_keys. A group referencing another group created by this layer is a Terraform dependency cycle, not something Cloudflare would report. Use group_ids for a group managed elsewhere, or merge the two rule sets."
  }
}
