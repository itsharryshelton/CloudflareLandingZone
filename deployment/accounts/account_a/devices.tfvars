# Account: account_a - Cloudflare One Client (WARP) device configuration.
# Consumed by the devices layer only.
#
#   terraform -chdir=layers/devices plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/devices.tfvars
#
# Platform defaults - client lock-down, allowed modes, the baseline split
# tunnel exclusions and fallback domains - are in layers/devices/defaults.auto.tfvars.
#
# Before the first apply:
#   - device_settings cannot be imported, so the first apply writes it whole.
#     Copy the four switches from the dashboard (Settings > Cloudflare One
#     Client > Global settings) rather than trusting the values below.
#   - the default profile is adopted by layers/devices/imports.tf. Read that
#     first plan line by line: anything left unset here goes to the provider's
#     default, not to what the dashboard holds.
#   - dashboard-made custom profiles are not matched by name. See imports.tf.
#
# Values are placeholders: RFC 5737 documentation ranges and RFC 2606 names.

device_settings = {
  gateway_proxy_enabled     = true
  gateway_udp_proxy_enabled = true

  # The Cloudflare root CA, which TLS decryption in the gateway layer needs on
  # every device. Leave false where MDM distributes the root instead.
  root_certificate_installation_enabled = false

  use_zt_virtual_ip = false

  # Support can issue an override code that turns the client off for an hour.
  disable_for_time = 3600
}

device_default_profile = {
  service_mode = { mode = "warp" }
  split_tunnel = {
    mode = "exclude"
    entries = [
      { host = "videoconf.example.com", description = "Latency-sensitive media, inspected at the vendor" },
    ]
  }

  # Internal names resolved by the office resolvers rather than Gateway.
  fallback_domains = {
    domains = [
      { suffix = "corp.example.com", description = "Internal zone", dns_servers = ["192.0.2.53", "192.0.2.54"] },
    ]
  }

  # Captive Portal time in seconds; giving time to login to it on public wifi.
  captive_portal = 180
  support_url    = "https://help.example.com/cloudflare-one"
}

device_custom_profiles = {
  # Engineers reach the lab ranges through a tunnel, so those ranges must not
  # be excluded. include_baseline = false drops the RFC 1918 exclusions, and
  # the LAN ranges that should still stay local are listed explicitly.
  engineering = {
    name       = "Engineering"
    precedence = 10
    match = {
      user_group_names = ["Platform Engineers"]
      os_names         = ["windows", "mac", "linux"]
    }

    service_mode = { mode = "warp" }

    split_tunnel = {
      mode             = "exclude"
      include_baseline = false
      entries = [
        { address = "192.168.0.0/16", description = "Home and office LANs" },
        { address = "169.254.0.0/16", description = "Link local" },
        { address = "fe80::/10", description = "IPv6 link local" },
      ]
    }

    fallback_domains = {
      domains = [
        { suffix = "corp.example.com", dns_servers = ["192.0.2.53", "192.0.2.54"] },
        { suffix = "lab.example.com", dns_servers = ["198.51.100.53"] },
      ]
    }
  }

  # Contractors: only the application range they are contracted for goes
  # through Cloudflare. Their own traffic is not ours to inspect.
  contractors = {
    name       = "Contractors"
    precedence = 20
    match = {
      user_group_names = ["Contractors"]
    }

    service_mode = { mode = "warp" }

    split_tunnel = {
      mode = "include"
      entries = [
        { address = "198.51.100.0/24", description = "Contracted application range" },
        { host = "app.example.com", description = "Contracted application" },
      ]
    }
  }
}
