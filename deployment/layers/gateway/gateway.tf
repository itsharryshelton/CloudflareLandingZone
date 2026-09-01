# Cloudflare Gateway (Secure Web Gateway): the DNS, network and HTTP policies
#
# One module instance per account. Gateway is account-scoped - no zone is
# involved - so there is no for_each here: the account is the run, and its ID
# comes from accounts/<account>/account.tfvars.
#
# Downstream deployments pin an immutable tag instead of the local path - review
# root readme.md for more info:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//gateway?ref=v1.0.0"
module "gateway" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//gateway"

  account_id = var.cloudflare_account_id

  policies = local.gateway_policies

  # Account-level configuration, not a rule. Cloudflare keeps one of these per
  # account and it always exists, so imports.tf adopts it rather than letting the
  # first apply write it from this configuration alone.
  settings = var.gateway_settings

  # The CA Gateway presents when it decrypts. Cloudflare provisions no
  # certificate with the account, so inspection cannot be enabled until one is
  # generated and activated - the module does both and points the configuration
  # above at the result.
  inspection_certificate = var.gateway_inspection_certificate

  allow_antivirus_fail_closed     = var.allow_antivirus_fail_closed
  allow_uninspected_http_policies = var.allow_uninspected_http_policies
}
