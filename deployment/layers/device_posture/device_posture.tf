# CF1 Device Posture
#
# Its own layer rather than part of zerotrust, because two layers consume it:
# Access policies in zerotrust and Gateway policies in gateway both take a
# posture rule's ID.
#
# One module instance per account.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/device_posture?ref=v1.0.0"
module "device_posture" {
  source = "../../../modules/device_posture"

  account_id = var.cloudflare_account_id

  integrations = local.integrations
  rules        = local.rules
}
