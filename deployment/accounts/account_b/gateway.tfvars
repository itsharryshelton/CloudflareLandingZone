# Account: account_b - Cloudflare Gateway (Secure Web Gateway).
#
# A smaller deployment than account_a: the platform threat baseline and one
# account rule, with no TLS inspection bypass and no DLP profiles yet.

gateway_baseline_policies = [
  "block_security_threats",
  "block_security_threats_http",
]

# Nothing is exempted from inspection on this account example.
gateway_bypass_applications = []

gateway_dlp_profile_ids       = []
gateway_quarantine_file_types = []

# The account's own address space, kept as a list so the policy below - and
# any later one - reads one maintained set of ranges rather than each carrying
# its own copy.
gateway_lists = {
  corporate_ranges = {
    name        = "Corporate source ranges"
    type        = "IP"
    description = "Every public range the account's sites and VPN egress from"
    items = [
      { value = "198.51.100.0/24", description = "Head office" },
      { value = "192.0.2.0/24", description = "Branch office" },
    ]
  }
}

gateway_blocked_content_categories = []

gateway_policies = {
  # Only the ranges the account actually operates from may reach the internet
  # through Gateway. `negate` inverts the whole compiled expression, which is
  # what makes a default-deny with a carve-out one rule rather than two.
  block_traffic_from_unknown_ranges = {
    name        = "Block traffic from unknown source ranges"
    type        = "network"
    action      = "block"
    precedence  = 100
    description = "Anything reaching Gateway from outside the account's own address space"

    match = {
      negate              = true
      source_ip_list_keys = ["corporate_ranges"]
    }

    settings = {
      block_reason = "This device is not on a network the organisation recognises."
    }
  }
}
