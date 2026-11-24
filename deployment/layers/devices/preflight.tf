resource "terraform_data" "preflight" {
  input = {
    device_settings_managed        = var.device_settings != null
    device_default_profile_managed = var.device_default_profile != null
    device_custom_profiles         = length(var.device_custom_profiles)
  }

  lifecycle {
    # An exclusion is invisible after the fact: excluded traffic never reaches
    # Gateway, so it is never logged, and every policy that should have seen it
    # still reads as enforced.
    precondition {
      condition     = length(local.broad_split_tunnel_excludes) == 0
      error_message = "These split tunnel exclusions take a broad slice of the internet out of the client, and so out of every Gateway policy: ${join("; ", local.broad_split_tunnel_excludes)}. Exclude the specific ranges or hosts that need it, use include mode if only a few destinations should go through Cloudflare, or set allow_broad_split_tunnel_excludes = true in layers/devices/defaults.auto.tfvars on a pull request that says why."
    }

    precondition {
      condition     = length(local.disallowed_service_modes) == 0
      error_message = "These profiles use a client mode outside allowed_device_service_modes (${join(", ", var.allowed_device_service_modes)}): ${join("; ", local.disallowed_service_modes)}. Every mode other than warp hides some traffic from Gateway - 1dot1 everything but DNS, posture_only everything. Use warp, or add the mode to allowed_device_service_modes in layers/devices/defaults.auto.tfvars on a pull request that says which devices need it."
    }
  }
}
