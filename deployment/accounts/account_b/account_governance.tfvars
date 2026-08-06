# Account: account_b - dashboard access.
#
# A smaller example than account_a: two people, one group. See
# accounts/account_a/account_governance.tfvars for deny policies and for scoping
# a policy to named resource groups.

account_members = {
  platform_admin = {
    email      = "platform.admin@example.net"
    role_names = ["Administrator Read Only"]
  }

  dns_operator = {
    email = "dns.operator@example.net"
  }
}

user_groups = {
  dns_operators = {
    name        = "DNS Operators"
    member_keys = ["dns_operator"]

    policies = [
      {
        permission_group_names = ["DNS Write", "Zone Read"]
      },
    ]
  }
}
