# Account: account_a - Device posture. Consumed by the device_posture layer only.
#
#   terraform -chdir=layers/device_posture plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/device_posture.tfvars
#
# A rule's ID comes out of this layer's device_posture_rule_ids output after it
# is first applied. Reference it from device_posture_ids in zerotrust.tfvars, or
# device_posture_check_ids in gateway.tfvars, on a later pull request - neither
# layer can read this one's state.
#
# NO CREDENTIAL GOES IN THIS FILE. A service provider integration's secret is
# set as the TF_VAR_DEVICE_POSTURE_INTEGRATION_SECRETS secret
#
#   {"intune":{"client_secret":"<Entra app registration client secret>"}}

device_posture_rules = {
  # The baseline most Access policies start from: the device is enrolled.
  require_client = {
    name = "Cloudflare One Client Running"
    type = "warp"
  }

  # One rule per platform - the check reads a different mechanism on each.
  disk_encryption_windows = {
    name      = "Disk Encrypted - Windows"
    type      = "disk_encryption"
    platforms = ["windows"]
    input     = { require_all = true }
  }

  disk_encryption_mac = {
    name      = "Disk Encrypted - macOS"
    type      = "disk_encryption"
    platforms = ["mac"]
    input     = { require_all = true }
  }

  # Full semver, always. "10.0" is not read as "10.0.0" and fails every device.
  windows_supported_build = {
    name      = "Windows 11 23H2 or Later"
    type      = "os_version"
    platforms = ["windows"]
    input = {
      operating_system = "windows"
      operator         = ">="
      version          = "10.0.22631"
    }
  }

  macos_supported_version = {
    name      = "macOS 14.4 or Later"
    type      = "os_version"
    platforms = ["mac"]
    input = {
      operating_system = "mac"
      operator         = ">="
      version          = "14.4.0"
    }
  }

  # enabled = true passes a device whose firewall is running. false would pass
  # one whose firewall is off, and the layer refuses it.
  firewall_windows = {
    name      = "Firewall Running - Windows"
    type      = "firewall"
    platforms = ["windows"]
    input = {
      operating_system = "windows"
      enabled          = true
    }
  }

  # The EDR sensor is running, and it is the vendor's binary: the thumbprint is
  # the signing certificate's SHA-1, which survives the vendor's updates where a
  # sha256 would not. Read it with Get-AuthenticodeSignature.
  falcon_sensor_windows = {
    name      = "CrowdStrike Falcon Sensor - Windows"
    type      = "application"
    platforms = ["windows"]
    input = {
      operating_system = "windows"
      path             = "%PROGRAMFILES%\\CrowdStrike\\CSFalconService.exe"
      thumbprint       = "0000000000000000000000000000000000000000"
    }
  }

  # Company-owned hardware: the serial number is on a Zero Trust list of type
  # "Serial numbers", maintained outside Terraform.
  # corporate_device = {
  #   name      = "Corporate Device"
  #   type      = "serial_number"
  #   platforms = ["windows", "mac", "linux"]
  #   input     = { list_id = "<Zero Trust list UUID>" }
  # }

  # Intune says the device is compliant. Needs the intune integration below.
  # intune_compliant = {
  #   name            = "Intune Compliant"
  #   type            = "intune"
  #   integration_key = "intune"
  #   input           = { compliance_status = "compliant" }
  # }
}

# Service provider integrations. Left commented because CI plans this layer
# offline, with no secrets: an integration without its credential fails the
# plan by design. Uncomment once TF_VAR_DEVICE_POSTURE_INTEGRATION_SECRETS is
# set in the account_a-plan environment.
#
# The Entra app registration needs Microsoft Graph
# DeviceManagementManagedDevices.Read.All as an application permission, with
# admin consent.
#
# device_posture_integrations = {
#   intune = {
#     name     = "Microsoft Intune"
#     type     = "intune"
#     interval = "10m"
#     config = {
#       client_id   = "00000000-0000-0000-0000-000000000000" # Application (client) ID
#       customer_id = "11111111-1111-1111-1111-111111111111" # Directory (tenant) ID
#     }
#   }
# }
