# Account: account_b - Device posture. Consumed by the device_posture layer only.
#
# A smaller example: an enrolled device with its disks encrypted. See
# accounts/account_a/device_posture.tfvars for the fuller worked example,
# including a service provider integration.

device_posture_rules = {
  require_client = {
    name = "Cloudflare One Client Running"
    type = "warp"
  }

  # iOS, Android and ChromeOS are always encrypted and have no disk check.
  disk_encryption = {
    name      = "Disk Encrypted"
    type      = "disk_encryption"
    platforms = ["windows", "mac", "linux"]
    input     = { require_all = true }
  }
}
