# Account: account_a - dashboard access.

account_members = {
  platform_admin = {
    email      = "platform.admin@example.com"
    role_names = ["Administrator Read Only"]
  }

  dns_operator = {
    email = "dns.operator@example.com"
    # No role_names, so this member gets default_role_names - enough to sign in and nothing else.
  }

  security_analyst = {
    email = "security.analyst@example.com"
  }
}

user_groups = {
  dns_operators = {
    name        = "DNS Operators"
    member_keys = ["dns_operator", "platform_admin"]

    policies = [
      {
        permission_group_names = ["DNS Write", "Zone Read"]
        # No resource_group_names, so the policy covers every zone in the account. Name one to narrow it.
      },
    ]
  }

  security_reviewers = {
    name        = "Security Reviewers"
    member_keys = ["security_analyst"]

    policies = [
      {
        permission_group_names = ["Firewall Services Read", "Zone Read", "Logs Read"]
      },
      {
        # Deny is evaluated before allow, so this carves DNS back out of the
        # grant above even if another policy or role would have permitted it.
        access                 = "deny"
        permission_group_names = ["DNS Write"]
      },
    ]
  }
}
