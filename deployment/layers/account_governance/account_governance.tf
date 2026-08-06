# Account memberships, user groups and group membership.
#
# One module instance per account, because one Cloudflare account is one set of
# people. There is no for_each here: the account is the run, and its ID comes
# from accounts/<account>/account.tfvars.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/account_governance?ref=v1.0.0"
module "account_governance" {
  source = "../../../modules/account_governance"

  account_id = var.cloudflare_account_id

  members     = local.members
  user_groups = local.user_groups
}
