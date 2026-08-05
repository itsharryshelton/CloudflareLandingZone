# Applies the health check policy and derives the preflight assertions.

locals {
  # Only zones a load balancer actually targets are looked up, so a DNS-only zone costs no API call.
  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains([for lb in var.load_balancers : lb.zone_key], key)
  }

  # Per-load-balancer settings win; anything unset falls back to the default health check policy.
  load_balancers = {
    for key, lb in var.load_balancers : key => merge(lb, {
      health_check = {
        type           = coalesce(lb.health_check.type, var.default_health_check.type)
        path           = coalesce(lb.health_check.path, var.default_health_check.path)
        port           = coalesce(lb.health_check.port, var.default_health_check.port)
        method         = coalesce(lb.health_check.method, var.default_health_check.method)
        expected_codes = coalesce(lb.health_check.expected_codes, var.default_health_check.expected_codes)
        interval       = coalesce(lb.health_check.interval, var.default_health_check.interval)
        timeout        = coalesce(lb.health_check.timeout, var.default_health_check.timeout)
        retries        = coalesce(lb.health_check.retries, var.default_health_check.retries)
      }
    })
  }

  # Preflight checks here
  dangling_zone_keys = [
    for key, lb in var.load_balancers : "load_balancers.${key}.zone_key = \"${lb.zone_key}\""
    if !contains(keys(var.zones), lb.zone_key)
  ]

  # Outside of zone rejection checks (Cloudflare rejects it, but only after the monitor and pool have been created, leaving a half-applied layer behind)
  hostnames_outside_zone = [
    for key, lb in var.load_balancers :
    "load_balancers.${key}: \"${lb.lb_hostname}\" is not within \"${var.zones[lb.zone_key].domain_name}\""
    if contains(keys(var.zones), lb.zone_key)
    && !endswith(lower(lb.lb_hostname), lower(var.zones[lb.zone_key].domain_name))
  ]
}
