# Cloudflare Gateway (Secure Web Gateway): the DNS, network and HTTP policies
#
# One module instance per account. Gateway is account-scoped - no zone is
# involved - so there is no for_each here: the account is the run, and its ID
# comes from accounts/<account>/account.tfvars.
#
# Downstream deployments pin an immutable tag instead of the local path - review
# root readme.md for more info:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/gateway?ref=v1.0.0"
module "gateway" {
  source = "../../../modules/gateway"

  account_id = var.cloudflare_account_id

  policies = local.gateway_policies
}
