# Rule sets, through the layer: the schema module, the key-to-name translation
# and the preflight checks that read rule sets.
#
# Offline. The provider is mocked and the organization lookup is overridden, so
# nothing here needs a token, an account or state.

mock_provider "cloudflare" {}

override_data {
  target = data.cloudflare_zero_trust_organization.this
  values = {
    auth_domain = "example.cloudflareaccess.com"
  }
}

variables {
  cloudflare_account_id     = "0123456789abcdef0123456789abcdef"
  identity_providers        = { entra_id = { name = "Entra ID", type = "azureAD" } }
  identity_provider_secrets = { entra_id = "not-a-real-secret" }
  service_tokens            = { ci = { name = "CI" } }
  access_groups = {
    staff     = { name = "Staff", include = { email_domains = ["example.com"] } }
    engineers = { name = "Engineers", include = { entra_groups = [{ identity_provider_key = "entra_id", group_id = "g" }] } }
  }
  access_policies = {
    staff = {
      name     = "Staff"
      decision = "allow"
      include  = { group_keys = ["staff"] }
      require  = { login_method_keys = ["entra_id"], auth_methods = ["mfa"] }
    }
    ci = { name = "CI", decision = "non_identity", include = { service_token_keys = ["ci"] } }
  }
}

# The two groups above set different rule attributes, which is the input that
# rules out `include = any` on a typed map: Terraform cannot unify the
# elements. It has to keep planning, and the keys have to arrive at the module
# as names.
run "keys_are_translated_to_names" {
  command = plan

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

  # Every attribute is present whatever was written. locals.tf reads all 23
  # without a try().
  assert {
    condition     = length(local.rule_sets["access_groups.staff.include"]) == 23
    error_message = "A rule set should carry all 23 attributes once typed."
  }

  assert {
    condition     = one([for policy in local.access_policies : policy.include.group_names if policy.name == "Staff"]) == ["Staff"]
    error_message = "group_keys should reach the module as the group's name."
  }

  assert {
    condition     = one([for policy in local.access_policies : policy.require.login_method_names if policy.name == "Staff"]) == ["Entra ID"]
    error_message = "login_method_keys should reach the module as the provider's name."
  }

  assert {
    condition     = one([for policy in local.access_policies : policy.include.service_token_names if policy.name == "CI"]) == ["CI"]
    error_message = "service_token_keys should reach the module as the token's name."
  }

  assert {
    condition     = one([for group in local.access_groups : group.include.entra_groups[0].identity_provider_name if group.name == "Engineers"]) == "Entra ID"
    error_message = "identity_provider_key should reach the module as the provider's name."
  }

  assert {
    condition     = alltrue([for policy in local.access_policies : policy.exclude == null])
    error_message = "A rule set that was not written should reach the module as null."
  }
}

# The point of declaring the type once: the same rule set means the same thing
# in all six positions.
run "all_six_positions_share_one_type" {
  command = plan

  variables {
    access_groups = {
      g = {
        name    = "G"
        include = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
        exclude = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
        require = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
      }
    }
    access_policies = {
      p = {
        name     = "P"
        decision = "allow"
        include  = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
        exclude  = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
        require  = { everyone = "true", country_codes = ["GB"], saml_attributes = [{ identity_provider_id = "x", attribute_name = "a", attribute_value = "b" }] }
      }
    }
  }

  assert {
    condition     = length(local.rule_sets) == 6 && length(distinct(values(local.rule_sets))) == 1
    error_message = "The same rule set written in all six positions should type to six identical objects."
  }
}

# A reference to a key that does not exist is dropped by the translation rather
# than passed on, so each run below keeps one condition that resolves. With
# none, the module would also refuse the rule set as empty, and the run would
# not show which check fired.
run "unknown_group_key_is_refused" {
  command = plan

  variables {
    access_policies = {
      staff = { name = "Staff", decision = "allow", include = { group_keys = ["staff", "nobody"] } }
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "unknown_service_token_key_is_refused" {
  command = plan

  variables {
    access_policies = {
      ci = { name = "CI", decision = "non_identity", include = { service_token_keys = ["ci", "nothing"] } }
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "unknown_login_method_key_is_refused" {
  command = plan

  variables {
    access_policies = {
      staff = { name = "Staff", decision = "allow", include = { everyone = true }, require = { login_method_keys = ["entra_id", "nothing"] } }
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "unknown_identity_provider_key_is_refused" {
  command = plan

  variables {
    access_groups = {
      engineers = { name = "Engineers", include = { email_domains = ["example.com"], saml_attributes = [{ identity_provider_key = "nothing", attribute_name = "a", attribute_value = "b" }] } }
    }
    access_policies = {}
  }

  expect_failures = [terraform_data.preflight]
}

# Not here: an identity provider reference carrying both a key and an ID, or
# neither. preflight.tf refuses it, and so does the precondition in
# modules/zerotrust, because the layer passes the reference on as written. A
# run cannot expect a failure from a resource inside a child module, so the two
# cannot be told apart from a test. modules/zerotrust/tests covers the
# module's half.

run "email_outside_the_allowed_domains_is_refused" {
  command = plan

  variables {
    allowed_email_domains = ["example.com"]
    access_groups = {
      staff = { name = "Staff", include = { emails = ["someone@example.org"] } }
    }
    access_policies = {}
  }

  expect_failures = [terraform_data.preflight]
}

# Only include admits anybody. Excluding an outside address narrows the
# audience, so the check leaves it alone.
run "excluding_an_outside_email_is_allowed" {
  command = plan

  variables {
    allowed_email_domains = ["example.com"]
    access_groups = {
      staff = { name = "Staff", include = { email_domains = ["Example.COM"] }, exclude = { emails = ["someone@example.org"] } }
    }
    access_policies = {}
  }
}

run "restricted_decision_is_refused" {
  command = plan

  variables {
    access_policies = {
      open = { name = "Open", decision = "bypass", include = { ip_cidrs = ["203.0.113.0/24"] } }
    }
  }

  expect_failures = [terraform_data.preflight]
}
