# The validation rules that live in modules/schema, run against it directly.
#
# They used to be on this module's own variables. `expect_failures` cannot name
# a variable of a child module, so a run through the parent can only show that
# the plan fails, not which rule failed it; each run here loads the schema
# module itself and names the variable.

variables {
  access_groups   = [{ name = "G", include = {} }]
  access_policies = [{ name = "P", decision = "allow", include = {} }]
  rule_sets = {
    "access_groups.g.include"   = { everyone = true }
    "access_policies.p.include" = { everyone = true }
  }
}

run "valid_input_passes" {
  command = plan

  module {
    source = "./modules/schema"
  }
}

run "group_without_a_name_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_groups = [{ name = " ", include = {} }]
  }

  expect_failures = [var.access_groups]
}

run "duplicate_group_names_are_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_groups = [{ name = "G", include = {} }, { name = " g ", include = {} }]
  }

  expect_failures = [var.access_groups]
}

run "group_names_inside_a_group_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    rule_sets = { "access_groups.g.require" = { group_names = ["Other"] } }
  }

  expect_failures = [var.rule_sets]
}

run "group_names_inside_a_policy_is_allowed" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    rule_sets = { "access_policies.p.include" = { group_names = ["G"] } }
  }
}

run "three_letter_country_code_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    rule_sets = { "access_policies.p.exclude" = { country_codes = ["GB", "GBR"] } }
  }

  expect_failures = [var.rule_sets]
}

run "bare_address_in_ip_cidrs_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    rule_sets = { "access_groups.g.include" = { ip_cidrs = ["203.0.113.7"] } }
  }

  expect_failures = [var.rule_sets]
}

run "bypass_for_everyone_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_policies = [{ name = "P", decision = "bypass", include = { everyone = true } }]
  }

  expect_failures = [var.access_policies]
}

run "bypass_for_a_named_range_is_allowed" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_policies = [{ name = "P", decision = "bypass", include = { ip_cidrs = ["203.0.113.0/24"] } }]
  }
}

run "duplicate_policy_names_are_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_policies = [
      { name = "P", decision = "allow", include = {} },
      { name = "p", decision = "deny", include = {} },
    ]
  }

  expect_failures = [var.access_policies]
}

run "unknown_decision_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_policies = [{ name = "P", decision = "permit", include = {} }]
  }

  expect_failures = [var.access_policies]
}

run "malformed_session_duration_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_policies = [{ name = "P", decision = "allow", session_duration = "8 hours", include = {} }]
  }

  expect_failures = [var.access_policies]
}

run "approval_required_without_approvers_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_policies = [{ name = "P", decision = "allow", approval_required = true, include = {} }]
  }

  expect_failures = [var.access_policies]
}

run "zero_approvals_needed_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_policies = [{
      name              = "P"
      decision          = "allow"
      approval_required = true
      approval_groups   = [{ approvals_needed = 0, email_addresses = ["approver@example.com"] }]
      include           = {}
    }]
  }

  expect_failures = [var.access_policies]
}
