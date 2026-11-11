# The validation rules that live in modules/schema, run against it directly.
#
# They used to be on this layer's own variables. `expect_failures` cannot name
# a variable of a child module, so a run through the layer can only show that
# the plan fails, not which rule failed it; each run here loads the schema
# module itself and names the variable.

variables {
  access_groups   = { staff = { name = "Staff", include = {} } }
  access_policies = { staff = { name = "Staff", decision = "allow", include = {} } }
  rule_sets = {
    "access_groups.staff.include"   = { email_domains = ["example.com"] }
    "access_policies.staff.include" = { group_keys = ["staff"] }
  }
}

run "valid_input_passes" {
  command = plan

  module {
    source = "./modules/schema"
  }
}

run "group_key_with_a_hyphen_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_groups = { "platform-engineers" = { name = "Platform Engineers", include = {} } }
  }

  expect_failures = [var.access_groups]
}

run "duplicate_group_names_are_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_groups = {
      staff = { name = "Staff", include = {} }
      other = { name = " staff ", include = {} }
    }
  }

  expect_failures = [var.access_groups]
}

run "group_keys_inside_a_group_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    rule_sets = { "access_groups.staff.exclude" = { group_keys = ["other"] } }
  }

  expect_failures = [var.rule_sets]
}

run "policy_key_with_a_space_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_policies = { "staff only" = { name = "Staff", decision = "allow", include = {} } }
  }

  expect_failures = [var.access_policies]
}

run "duplicate_policy_names_are_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_policies = {
      staff = { name = "Staff", decision = "allow", include = {} }
      other = { name = "STAFF", decision = "deny", include = {} }
    }
  }

  expect_failures = [var.access_policies]
}

run "unknown_decision_is_refused" {
  command = plan

  module {
    source = "./modules/schema"
  }

  variables {
    access_policies = { staff = { name = "Staff", decision = "permit", include = {} } }
  }

  expect_failures = [var.access_policies]
}
