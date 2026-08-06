# Account: account_b - Zero Trust Access.
#
# A smaller example: one login method, one audience, one application. The team
# name is left unset, so the layer adopts whatever team name the account already has rather than asserting one.

identity_providers = {
  entra_id = {
    name = "Entra ID"
    type = "azureAD"

    config = {
      client_id      = "00000000-0000-0000-0000-000000000000"
      directory_id   = "33333333-3333-3333-3333-333333333333"
      support_groups = true
    }
  }
}

access_groups = {
  staff = {
    name    = "Staff"
    include = { email_domains = ["example.net"] }
  }
}

access_policies = {
  staff_only = {
    name     = "Staff Only"
    decision = "allow"
    include  = { group_keys = ["staff"] }
  }
}

access_applications = {
  internal_wiki = {
    name        = "Internal Wiki"
    domain      = "wiki.example.net"
    policy_keys = ["staff_only"]

    app_launcher_visible = true
  }
}
