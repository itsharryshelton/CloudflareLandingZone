# Load_balancing - inputs.
#
# Health monitors, origin pools and load balancers. Runs after zones and holds its own state, so an apply here can never propose destroying a zone.
#
# Config files:
#   accounts/<account>/zones.tfvars          - the zone inventory, shared with every layer
#   accounts/<account>/load_balancing.tfvars - load balancers, consumed only here

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Used both to scope the zone lookup and directly by the module - Cloudflare monitors and pools are account-scoped resources."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: logical key => domain name. The same file the zones layer is
    given, so the keys mean the same thing in both.

    This layer does not create zones. It looks each referenced domain up by name to
    get its ID (see zone_lookup.tf), which keeps the two layers' states
    independent.

    - `domain_name` - The apex domain (e.g. example.com).
    - `zone_tier`   - (Optional) The zone's Cloudflare rate plan. Unused by this
                      layer, and declared only so that the shared inventory file
                      can carry it for the zones and waf layers, which do gate on
                      it. Terraform rejects a .tfvars attribute that the variable
                      type does not declare, so omitting it here would break
                      every layer's run rather than just this one's.
  EOT
  type = map(object({
    domain_name = string
    zone_tier   = optional(string)
  }))

  validation {
    condition     = alltrue([for key in keys(var.zones) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "zones keys must be lowercase alphanumeric with underscores."
  }
}

variable "load_balancers" {
  description = <<-EOT
    A map of load balancers, keyed by a logical key. One origin pool and one health
    monitor are created per entry.

    - `zone_key`                - The key of the zone hosting the hostname. Taken from `var.zones`.
    - `lb_hostname`             - Fully-qualified hostname the load balancer answers on.
                                  Must sit within the referenced zone's domain.
    - `origins`                 - Origin servers. `weight` is 0.0-1.0. `header_host` is a
                                  list, because Cloudflare models the Host override as a list.
    - `proxied`                 - (Optional) Proxy the hostname through Cloudflare. Defaults to true.
    - `steering_policy`         - (Optional) Null lets Cloudflare fail over in pool order.
    - `session_affinity`        - (Optional) none, cookie, ip_cookie or header.
    - `pool_minimum_origins`    - (Optional) Minimum healthy origins. Cannot exceed the origin count.
    - `pool_notification_email` - (Optional) Address notified on pool health changes.
    - `health_check`            - (Optional) Monitor settings. Any field left unset falls back
                                  to `var.default_health_check`, so the fleet policy can be
                                  changed in one place.
  EOT
  type = map(object({
    zone_key    = string
    lb_hostname = string
    origins = list(object({
      name        = string
      address     = string
      enabled     = optional(bool, true)
      weight      = optional(number, 1)
      port        = optional(number)
      header_host = optional(list(string))
    }))
    proxied                 = optional(bool, true)
    steering_policy         = optional(string)
    session_affinity        = optional(string, "none")
    pool_minimum_origins    = optional(number, 1)
    pool_notification_email = optional(string)

    # No inner defaults on purpose: an unset field must stay null so
    # var.default_health_check can supply it. See locals.tf.
    health_check = optional(object({
      type           = optional(string)
      path           = optional(string)
      port           = optional(number)
      method         = optional(string)
      expected_codes = optional(string)
      interval       = optional(number)
      timeout        = optional(number)
      retries        = optional(number)
    }), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.load_balancers) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "load_balancers keys must be lowercase alphanumeric with underscores."
  }

  validation {
    condition     = length(distinct([for lb in var.load_balancers : lower(lb.lb_hostname)])) == length(var.load_balancers)
    error_message = "Each load_balancers entry must have a distinct lb_hostname."
  }
}

# Platform defaults (defaults.auto.tfvars in this directory)
variable "default_health_check" {
  description = <<-EOT
    Fleet-wide health check policy. Supplies any `health_check` field a load
    balancer leaves unset, so the monitoring posture can be changed once rather
    than per load balancer.
  EOT
  type = object({
    type           = optional(string, "https")
    path           = optional(string, "/healthz")
    port           = optional(number, 443)
    method         = optional(string, "GET")
    expected_codes = optional(string, "2xx")
    interval       = optional(number, 60)
    timeout        = optional(number, 5)
    retries        = optional(number, 2)
  })
  default = {}
}
