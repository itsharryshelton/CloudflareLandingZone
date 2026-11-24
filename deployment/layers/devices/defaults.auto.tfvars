# Layer devices - platform baseline. Auto-loaded from this directory.

# A managed device stays in Gateway. Users cannot switch the client off, log
# the device out of the organisation, or move it to a mode Gateway sees less
# of. Override per profile in devices.tfvars where a population needs it, and
# give support an admin override code (device_settings.disable_for_time).
default_device_switch_locked     = true
default_device_allowed_to_leave  = false
default_device_allow_mode_switch = false

# Traffic and DNS: the only mode in which every Gateway policy type applies.
# Add posture_only for devices that should report posture without being
# filtered, or 1dot1 for DNS-only filtering, on a pull request that says why.
allowed_device_service_modes = ["warp"]

# An exclusion broader than a /8 of routable space takes most traffic out of
# Gateway while the policies still read as enforced.
allow_broad_split_tunnel_excludes = false

# Cloudflare's default split tunnel exclusions: private, CGNAT, link-local,
# multicast and reserved ranges. Prepended to every exclude-mode list, because
# a managed list replaces Cloudflare's own. Remove a range here (or set
# include_baseline = false on the profile) to send it through the client - for
# example 10.0.0.0/8 when private network routes are served by a tunnel.
# If device_settings.use_zt_virtual_ip is true, devices are addressed from
# 100.96.0.0/12, inside 100.64.0.0/10; drop that entry for device-to-device
# traffic to reach the tunnel.
baseline_split_tunnel_excludes = [
  { address = "10.0.0.0/8" },
  { address = "100.64.0.0/10" },
  { address = "169.254.0.0/16", description = "DHCP unspecified" },
  { address = "172.16.0.0/12" },
  { address = "192.0.0.0/24" },
  { address = "192.168.0.0/16" },
  { address = "224.0.0.0/24" },
  { address = "240.0.0.0/4" },
  { address = "255.255.255.255/32", description = "DHCP broadcast" },
  { address = "fe80::/10", description = "IPv6 link local" },
  { address = "fd00::/8" },
  { address = "ff01::/16" },
  { address = "ff02::/16" },
  { address = "ff03::/16" },
  { address = "ff04::/16" },
  { address = "ff05::/16" },
]

# Cloudflare's default Local Domain Fallback suffixes: names that only exist on
# a local network and that Gateway cannot resolve. Prepended to every managed
# list, because a managed list replaces Cloudflare's defaults.
baseline_fallback_domains = [
  { suffix = "intranet" },
  { suffix = "internal" },
  { suffix = "private" },
  { suffix = "localdomain" },
  { suffix = "domain" },
  { suffix = "lan" },
  { suffix = "home" },
  { suffix = "host" },
  { suffix = "corp" },
  { suffix = "local" },
  { suffix = "localhost" },
  { suffix = "home.arpa" },
  { suffix = "invalid" },
  { suffix = "test" },
]
