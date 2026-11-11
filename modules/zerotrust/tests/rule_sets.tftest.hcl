# Rule sets, through the module: what the schema module does to them, and the
# preconditions in main.tf that read the result.
#
# Offline. The provider is mocked, so nothing here needs a token or an account.

mock_provider "cloudflare" {}

variables {
  account_id         = "0123456789abcdef0123456789abcdef"
  identity_providers = [{ name = "Entra ID", type = "azureAD" }]
  service_tokens     = [{ name = "CI" }]
}

# Two groups that set different rule attributes are the input that rules out
# `include = any` on a typed list: Terraform cannot unify the elements. It has
# to keep planning.
run "groups_setting_different_attributes_plan" {
  command = plan

  variables {
    access_groups = [
      { name = "Staff", include = { email_domains = ["example.com"] } },
      { name = " Engineers ", include = { entra_groups = [{ identity_provider_name = "Entra ID", group_id = "g" }] }, exclude = null },
    ]
    access_policies = [
      {
        name     = "Staff"
        decision = "allow"
        include  = { group_names = ["Staff"] }
        require  = { login_method_names = ["Entra ID"], auth_methods = ["mfa"] }
      },
      { name = "CI", decision = "non_identity", include = { service_token_names = ["CI"] } },
    ]
  }

  # An omitted exclude and an explicit null are both "no rule set".
  assert {
    condition = sort(keys(local.rule_sets)) == tolist([
      "access_groups.engineers.include",
      "access_groups.staff.include",
      "access_policies.ci.include",
      "access_policies.staff.include",
      "access_policies.staff.require",
    ])
    error_message = "The rule sets are not the five that were written: ${join(", ", keys(local.rule_sets))}."
  }

  # Every attribute is present whatever was written, and defaults to "plays no
  # part". locals.tf reads all 23 without a try().
  assert {
    condition     = length(local.rule_sets["access_groups.staff.include"]) == 23
    error_message = "A rule set should carry all 23 attributes once typed."
  }

  assert {
    condition = alltrue([
      for attribute, value in local.rule_sets["access_groups.staff.include"] :
      try(length(value) == 0, value == false)
      if attribute != "email_domains"
    ])
    error_message = "An attribute that was not written should default to false or an empty list."
  }

  assert {
    condition     = local.rule_terms_base["access_groups.staff.include"] == [{ email_domain = { domain = "example.com" } }]
    error_message = "email_domains should become one email_domain term."
  }

  assert {
    condition     = length(local.policy_rule_terms["access_policies.staff.require"]) == 2
    error_message = "require should carry an auth_method and a login_method term."
  }

  assert {
    condition     = length(local.access_policies["staff"].approval_groups) == 0
    error_message = "approval_groups should default to an empty list."
  }
}

# The point of declaring the type once: the same rule set means the same thing
# in all six positions.
run "all_six_positions_share_one_type" {
  command = plan

  variables {
    access_groups = [{
      name    = "G"
      include = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
      exclude = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
      require = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
    }]
    access_policies = [{
      name     = "P"
      decision = "allow"
      include  = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
      exclude  = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
      require  = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
    }]
  }

  assert {
    condition     = length(local.rule_sets) == 6 && length(distinct(values(local.rule_sets))) == 1
    error_message = "The same rule set written in all six positions should type to six identical objects."
  }

  assert {
    condition     = local.rule_sets["access_policies.p.exclude"].everyone == true
    error_message = "everyone = \"true\" should convert to a bool, as it did when the type was on the variable."
  }
}

# Pinned so that changing it is a decision: Terraform drops an attribute the
# type does not declare, without a word. It did the same when the type was on
# the variable.
run "misspelt_attribute_is_dropped_silently" {
  command = plan

  variables {
    access_groups = [{
      name    = "Staff"
      include = { email_domains = ["example.com"], emials = ["someone@example.org"] }
      exlcude = { everyone = true }
    }]
  }

  assert {
    condition     = sort(keys(local.rule_sets)) == tolist(["access_groups.staff.include"]) && length(local.rule_terms_base["access_groups.staff.include"]) == 1
    error_message = "A misspelt attribute should be dropped, leaving the one condition that was spelt correctly."
  }
}

run "empty_group_rule_set_is_refused" {
  command = plan

  variables {
    access_groups = [{ name = "Staff", include = { email_domains = ["example.com"] }, require = {} }]
  }

  expect_failures = [cloudflare_zero_trust_access_group.this]
}

# The same precondition is how a rule set whose only attribute is misspelt gets
# caught.
run "rule_set_with_only_a_misspelt_attribute_is_refused" {
  command = plan

  variables {
    access_groups = [{ name = "Staff", include = { emials = ["someone@example.com"] } }]
  }

  expect_failures = [cloudflare_zero_trust_access_group.this]
}

run "empty_policy_rule_set_is_refused" {
  command = plan

  variables {
    access_policies = [{ name = "P", decision = "allow", include = { everyone = true }, exclude = {} }]
  }

  expect_failures = [cloudflare_zero_trust_access_policy.this]
}

run "unknown_group_name_is_refused" {
  command = plan

  variables {
    access_policies = [{ name = "P", decision = "allow", include = { group_names = ["Nobody"] } }]
  }

  expect_failures = [cloudflare_zero_trust_access_policy.this]
}

run "unknown_service_token_name_is_refused" {
  command = plan

  variables {
    access_groups = [{ name = "G", include = { everyone = true }, exclude = { service_token_names = ["Nothing"] } }]
  }

  expect_failures = [cloudflare_zero_trust_access_group.this]
}

run "unknown_login_method_name_is_refused" {
  command = plan

  variables {
    access_policies = [{ name = "P", decision = "allow", include = { everyone = true }, require = { login_method_names = ["Nothing"] } }]
  }

  expect_failures = [cloudflare_zero_trust_access_policy.this]
}

run "unknown_identity_provider_name_is_refused" {
  command = plan

  variables {
    access_groups = [{ name = "G", include = { oidc_claims = [{ identity_provider_name = "Nothing", claim_name = "a", claim_value = "b" }] } }]
  }

  expect_failures = [cloudflare_zero_trust_access_group.this]
}

run "identity_provider_name_and_id_together_are_refused" {
  command = plan

  variables {
    access_groups = [{ name = "G", include = { entra_groups = [{ identity_provider_name = "Entra ID", identity_provider_id = "x", group_id = "g" }] } }]
  }

  expect_failures = [cloudflare_zero_trust_access_group.this]
}

run "identity_provider_reference_with_neither_is_refused" {
  command = plan

  variables {
    access_policies = [{ name = "P", decision = "allow", include = { entra_auth_contexts = [{ id = "a", ac_id = "b" }] } }]
  }

  expect_failures = [cloudflare_zero_trust_access_policy.this]
}
