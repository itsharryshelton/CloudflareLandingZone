# Zero Trust Access: the organization, its login methods, its audiences and the
# applications behind it.
#
# One module instance per account, because one Cloudflare account is one Zero
# Trust organization. There is no for_each here: the account is the run, and its
# ID comes from accounts/<account>/account.tfvars.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/zerotrust?ref=v1.0.0"
module "zerotrust" {
  source = "../../../modules/zerotrust"

  account_id = var.cloudflare_account_id

  organization        = local.organization
  identity_providers  = local.identity_providers
  service_tokens      = local.service_tokens
  access_groups       = local.access_groups
  access_policies     = local.access_policies
  access_applications = local.access_applications
}
