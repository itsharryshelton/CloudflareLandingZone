# Cloudflare One Client (WARP) device configuration: account device settings,
# the default device profile, custom profiles, split tunnels and Local Domain
# Fallback.
#
# Its own layer rather than part of gateway or device_posture. Every token in
# the three holds the same Zero Trust grant, so the reason is review, not
# scope: a profile change decides what traffic Gateway sees at all, and a bad
# split tunnel or a disabled proxy takes a fleet out of filtering - or off the
# network - with nothing in the gateway layer's plan to show it.
#
# One module instance per account.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//device_profiles?ref=v1.0.0"
module "device_profiles" {
  source = "../../../modules/device_profiles"

  account_id = var.cloudflare_account_id

  # Account singleton. Provider 5.23 cannot import it, so the module requires
  # every switch to be stated - see modules/device_profiles/variables.tf.
  device_settings = var.device_settings

  # Account singleton, adopted by the import block in imports.tf.
  default_profile = local.default_profile

  custom_profiles = local.custom_profiles
}
