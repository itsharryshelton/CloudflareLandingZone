# Applies the platform baseline - client lock-down defaults, the baseline split
# tunnel exclusions and fallback domains - and derives the preflight
# assertions, so that devices.tf reads as a plain module call.
#
# Shape and per-profile validity (a CIDR that is not one, an include list with
# nothing in it, two profiles on one precedence) are the module's checks, so
# they hold for any consumer of it. What is here is this platform's policy.

locals {
  # A profile's split tunnel, with the baseline prepended in exclude mode. An
  # entry the profile lists itself is not repeated, so the profile's own
  # description wins.
  custom_profiles = {
    for key, p in var.device_custom_profiles : key => merge(p, {
      switch_locked     = coalesce(p.switch_locked, var.default_device_switch_locked)
      allowed_to_leave  = coalesce(p.allowed_to_leave, var.default_device_allowed_to_leave)
      allow_mode_switch = coalesce(p.allow_mode_switch, var.default_device_allow_mode_switch)

      split_tunnel = p.split_tunnel == null ? null : {
        mode = p.split_tunnel.mode
        entries = concat(
          p.split_tunnel.mode == "exclude" && p.split_tunnel.include_baseline ? [
            for b in var.baseline_split_tunnel_excludes : b
            if !contains([for e in p.split_tunnel.entries : lower(trimspace(coalesce(e.address, e.host, " ")))], lower(trimspace(coalesce(b.address, b.host, " "))))
          ] : [],
          p.split_tunnel.entries,
        )
      }

      fallback_domains = p.fallback_domains == null ? null : concat(
        p.fallback_domains.include_baseline ? [
          for b in var.baseline_fallback_domains : b
          if !contains([for d in p.fallback_domains.domains : lower(trimspace(d.suffix))], lower(trimspace(b.suffix)))
        ] : [],
        p.fallback_domains.domains,
      )
    })
  }

  # Same treatment for the default profile. Built through a for so that a null
  # default profile simply produces nothing.
  default_profile = one([
    for p in [var.device_default_profile] : merge(p, {
      switch_locked     = coalesce(p.switch_locked, var.default_device_switch_locked)
      allowed_to_leave  = coalesce(p.allowed_to_leave, var.default_device_allowed_to_leave)
      allow_mode_switch = coalesce(p.allow_mode_switch, var.default_device_allow_mode_switch)

      split_tunnel = p.split_tunnel == null ? null : {
        mode = p.split_tunnel.mode
        entries = concat(
          p.split_tunnel.mode == "exclude" && p.split_tunnel.include_baseline ? [
            for b in var.baseline_split_tunnel_excludes : b
            if !contains([for e in p.split_tunnel.entries : lower(trimspace(coalesce(e.address, e.host, " ")))], lower(trimspace(coalesce(b.address, b.host, " "))))
          ] : [],
          p.split_tunnel.entries,
        )
      }

      fallback_domains = p.fallback_domains == null ? null : concat(
        p.fallback_domains.include_baseline ? [
          for b in var.baseline_fallback_domains : b
          if !contains([for d in p.fallback_domains.domains : lower(trimspace(d.suffix))], lower(trimspace(b.suffix)))
        ] : [],
        p.fallback_domains.domains,
      )
    }) if p != null
  ])

  # One view of every managed profile, as it will be sent, labelled the way an
  # error message should name it.
  default_profile_by_label = { device_default_profile = local.default_profile }

  effective_profiles = merge(
    {
      for key, p in local.custom_profiles : "device_custom_profiles.${key}" => {
        split_mode   = try(p.split_tunnel.mode, null)
        entries      = p.split_tunnel == null ? [] : p.split_tunnel.entries
        service_mode = try(p.service_mode.mode, null)
      }
    },
    {
      for label, p in local.default_profile_by_label : label => {
        split_mode   = try(p.split_tunnel.mode, null)
        entries      = p.split_tunnel == null ? [] : p.split_tunnel.entries
        service_mode = try(p.service_mode.mode, null)
      } if p != null
    },
  )

  # Derived assertions, consumed by preflight.tf.

  # Broader than a /8, and not inside the multicast and reserved space
  # (224.0.0.0/3) or IPv6 unique local space (fc00::/7) that Cloudflare's own
  # default list excludes. A malformed address is the module's to report, so
  # try() treats it as not broad here.
  broad_split_tunnel_excludes = var.allow_broad_split_tunnel_excludes ? [] : sort(flatten([
    for label, p in local.effective_profiles : [
      for e in p.entries : "${label} -> ${trimspace(coalesce(e.address, e.host, ""))}"
      if p.split_mode == "exclude" && (
        e.address != null ? try(
          tonumber(split("/", trimspace(e.address))[1]) < 8 && !(
            strcontains(e.address, ":")
            ? tonumber(split("/", trimspace(e.address))[1]) >= 7 && cidrsubnet("${cidrhost(lower(trimspace(e.address)), 0)}/7", 0, 0) == "fc00::/7"
            : tonumber(split("/", trimspace(e.address))[1]) >= 3 && cidrsubnet("${cidrhost(trimspace(e.address), 0)}/3", 0, 0) == "224.0.0.0/3"
          ),
          false,
        )
        : (e.host != null && startswith(lower(trimspace(coalesce(e.host, ""))), "*.") && length(split(".", trimprefix(lower(trimspace(coalesce(e.host, ""))), "*."))) == 1)
      )
    ]
  ]))

  disallowed_service_modes = sort([
    for label, p in local.effective_profiles : "${label} -> \"${p.service_mode}\""
    if p.service_mode != null && !contains(var.allowed_device_service_modes, coalesce(p.service_mode, "x"))
  ])
}
