# Minimal usage example, and the fixture module CI plans offline.
#
# CI plans this with a dummy API token, so it must stay offline-plannable: no
# data sources, and every input a literal. The IDs are placeholders from no real
# account; keep them that way so the example stays customer-agnostic.

terraform {
  required_version = ">= 1.12.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.7"
    }
  }
}

# Reads CLOUDFLARE_API_TOKEN. An offline plan only creates, so it is never used.
provider "cloudflare" {}

module "account_governance" {
  source = "../.."

  account_id = "0123456789abcdef0123456789abcdef"

  members = [
    {
      email    = "ops@example.com"
      role_ids = ["0123456789abcdef0123456789abcde1"]
    },
  ]

  # Names a declared member by address, so the group membership resource is
  # planned too and the email-to-membership-ID resolution is exercised.
  user_groups = [
    {
      name          = "Platform operators"
      member_emails = ["ops@example.com"]
      policies = [
        {
          permission_group_ids = ["0123456789abcdef0123456789abcde2"]
          resource_group_ids   = ["0123456789abcdef0123456789abcde3"]
        },
      ]
    },
  ]
}
