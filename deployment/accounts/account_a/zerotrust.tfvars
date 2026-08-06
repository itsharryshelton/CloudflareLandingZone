# Account: account_a - Zero Trust Access.
#
# The team name must already exist on the account - see GETTING_STARTED.md
zero_trust_team_name         = "account-a"
zero_trust_organization_name = "Account A Internal Applications"

identity_providers = {
  entra_id = {
    name = "Entra ID"
    type = "azureAD"

    config = {
      # Application (client) ID and tenant (directory) ID from the Entra app
      # registration. The client secret comes from the pipeline as TF_VAR_identity_provider_secrets, keyed "entra_id".
      client_id    = "00000000-0000-0000-0000-000000000000"
      directory_id = "11111111-1111-1111-1111-111111111111"

      # Without this, Entra never sends group membership and every entra_groups rule below silently matches nobody.
      support_groups = true

      # Conditional Access authentication contexts. A policy can require one.
      conditional_access_enabled = true
    }

    # SCIM provisioning. User or seat deprovision in Entra removes Cloudflare access.
    scim_config = {
      enabled          = true
      user_deprovision = true
      seat_deprovision = true
    }
  }
}

service_tokens = {
  ci_pipeline = {
    name = "CI Pipeline"
    # No duration, so it gets default_service_token_duration - a year.
  }
}

access_groups = {
  platform_engineers = {
    name = "Platform Engineers"

    include = {
      # The Entra group's object ID, from Entra, not a name.
      entra_groups = [
        { identity_provider_key = "entra_id", group_id = "22222222-2222-2222-2222-222222222222" },
      ]
    }
  }

  staff = {
    name    = "Staff"
    include = { email_domains = ["example.com"] }
  }
}

access_policies = {
  # Deny first: Cloudflare evaluates policies in the order an application lists
  # them, and the first match decides.
  block_untrusted_countries = {
    name     = "Block Untrusted Countries"
    decision = "deny"
    include  = { country_codes = ["KP"] }
  }

  platform_engineers_mfa = {
    name             = "Platform Engineers with MFA"
    decision         = "allow"
    session_duration = "8h"
    include          = { group_keys = ["platform_engineers"] }

    # auth_methods asserts the identity provider said MFA happened. It is not
    # Cloudflare prompting for a second factor.
    require = {
      auth_methods      = ["mfa"]
      login_method_keys = ["entra_id"]
    }
  }

  ci_service_token = {
    name     = "CI Pipeline Service Token"
    decision = "non_identity"
    include  = { service_token_keys = ["ci_pipeline"] }
  }
}

access_applications = {
  grafana = {
    name   = "Grafana"
    domain = "grafana.example.com"

    # Anything else the same application answers on. `domain` above is added to
    # the destinations Cloudflare secures automatically, so it is not repeated
    # here. Every hostname listed needs a proxied DNS record of its own.
    extra_destinations = [
      { uri = "metrics.example.com" },
    ]

    # In evaluation order.
    policy_keys = ["block_untrusted_countries", "platform_engineers_mfa", "ci_service_token"]

    session_duration     = "8h"
    app_launcher_visible = true

    # The CI pipeline calls this, so a failed authentication should be a 401 and
    # not a page of login HTML.
    service_auth_401_redirect = true
  }
}
