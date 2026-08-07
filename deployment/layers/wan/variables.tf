# Layer wan - inputs.
#
# Cloudflare WAN (formerly Magic WAN): the GRE and IPsec tunnels between a
# customer network and Cloudflare's edge, and the static routes that decide what
# goes down them. Holds its own state, so an apply here can never propose
# destroying a zone.
#
# No zone is involved anywhere in this layer, so it looks nothing up and can be
# planned offline.
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/wan.tfvars     - the tunnels and routes, consumed only here
#
# And, from the apply environment rather than any file:
#   TF_VAR_wan_ipsec_tunnel_psks      - the pre-shared keys
#   TF_VAR_wan_bgp_md5_keys           - BGP session keys, if any tunnel peers
#
# CLOUDFLARE WAN IS NOT ENABLED HERE. It is an Enterprise entitlement that
# Cloudflare switches on when it is bought; there is no resource that could turn
# it on, and an account without it fails every call in this layer on
# authorisation rather than on quota. Magic Transit and Magic Firewall are
# separate products and deliberately out of scope.

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Cloudflare WAN tunnels and routes are account-scoped resources."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "wan_gre_tunnels" {
  description = <<-EOT
    GRE tunnels, keyed by a logical key.

    The key is the Terraform address and `name` is the tunnel's identity in
    Cloudflare. Changing either destroys and recreates the tunnel, which drops
    the traffic on it.

    GRE encapsulates but does not encrypt. Use it over a private circuit or a
    Cloudflare Network Interconnect; over the public internet use
    `wan_ipsec_tunnels`, whose payload is encrypted.

    - `name`                    - Up to 15 characters, letters, numbers,
                                  underscores and hyphens. Unique across every
                                  tunnel on the account, GRE and IPsec alike.
    - `cloudflare_endpoint`     - The anycast IP Cloudflare allocated to this
                                  account. Cloudflare's to give, not yours to pick.
    - `customer_endpoint`       - The public IP of the device at your end.
    - `interface_address`       - The /31 the tunnel is numbered from, taken from
                                  private space. The address written is
                                  Cloudflare's side of it.
    - `interface_address6`      - (Optional) The equivalent /127 for IPv6.
    - `description`             - (Optional) Free text, shown in the dashboard.
    - `mtu`                     - (Optional) Falls back to
                                  `var.default_gre_tunnel_mtu`.
    - `ttl`                     - (Optional) Falls back to
                                  `var.default_gre_tunnel_ttl`.
    - `automatic_return_routing`- (Optional) Falls back to
                                  `var.default_automatic_return_routing`.
    - `health_check_*`          - (Optional) Per-tunnel overrides of the four
                                  `var.default_tunnel_health_check_*` values.
                                  `health_check_target` has no fleet default: it
                                  is the address a request-type check is forwarded
                                  to once the tunnel decapsulates it, and
                                  Cloudflare defaults it to the customer endpoint.
    - `bgp_customer_asn`        - (Optional) Set it and the tunnel runs a BGP
                                  session instead of relying on static routes.
                                  The session key, if one is wanted, comes from
                                  `var.wan_bgp_md5_keys` keyed by this same key.
    - `bgp_extra_prefixes`      - (Optional) Prefixes advertised to your device on
                                  top of the Magic routing table.
  EOT
  type = map(object({
    name                = string
    cloudflare_endpoint = string
    customer_endpoint   = string
    interface_address   = string
    interface_address6  = optional(string)
    description         = optional(string)

    mtu                      = optional(number)
    ttl                      = optional(number)
    automatic_return_routing = optional(bool)

    health_check_enabled   = optional(bool)
    health_check_direction = optional(string)
    health_check_rate      = optional(string)
    health_check_type      = optional(string)
    health_check_target    = optional(string)

    bgp_customer_asn   = optional(number)
    bgp_extra_prefixes = optional(list(string))
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.wan_gre_tunnels) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "wan_gre_tunnels keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  # Checked here as well as in the module because this layer does arithmetic on
  # the /31 to work out each tunnel's customer-side address, and a malformed one
  # should name the operator's own input rather than a module variable.
  validation {
    condition = alltrue([
      for tunnel in var.wan_gre_tunnels :
      endswith(tunnel.interface_address, "/31") && can(cidrnetmask(tunnel.interface_address))
    ])
    error_message = "Each wan_gre_tunnels[*].interface_address must be an IPv4 /31 from private space, e.g. \"10.252.0.0/31\". Cloudflare numbers a tunnel from a two-host subnet: the address written is its side, the other host is yours."
  }

  validation {
    condition = alltrue([
      for tunnel in var.wan_gre_tunnels :
      tunnel.interface_address6 == null || (
        endswith(coalesce(tunnel.interface_address6, "::/0"), "/127")
        && can(cidrhost(coalesce(tunnel.interface_address6, "::/0"), 1))
      )
    ])
    error_message = "Each wan_gre_tunnels[*].interface_address6, when set, must be an IPv6 /127."
  }
}

variable "wan_ipsec_tunnels" {
  description = <<-EOT
    IPsec tunnels, keyed by a logical key. The site-to-site option, and the right
    one over the public internet.

    - `name`                        - Up to 15 characters, letters, numbers,
                                      underscores and hyphens. Unique across every
                                      tunnel on the account.
    - `cloudflare_endpoint`         - The anycast IP Cloudflare allocated to this
                                      account.
    - `customer_endpoint`           - (Optional) The public IP of your device.
                                      Cloudflare does not need it to bring the
                                      tunnel up - your end always initiates - but
                                      proactive traceroutes will not work without
                                      it. Leave it out for a dynamic address.
    - `interface_address`           - The /31 the tunnel is numbered from. The
                                      address written is Cloudflare's side.
    - `interface_address6`          - (Optional) The equivalent /127 for IPv6.
    - `description`                 - (Optional) Free text, shown in the dashboard.
    - `replay_protection`           - (Optional) Falls back to
                                      `var.default_ipsec_replay_protection`.
    - `automatic_return_routing`    - (Optional) Falls back to
                                      `var.default_automatic_return_routing`.
    - `custom_remote_identity_label`- (Optional) A single DNS label. The layer
                                      builds the full custom IKE FQDN identity
                                      around it, account ID included, for a device
                                      that cannot present the generated IKE ID.
    - `health_check_*`              - (Optional) As on `wan_gre_tunnels`.
    - `bgp_customer_asn`,
      `bgp_extra_prefixes`          - (Optional) As on `wan_gre_tunnels`.

    THE PRE-SHARED KEY IS NOT DECLARED HERE. It comes from
    `var.wan_ipsec_tunnel_psks`, keyed the same way as this map, and that arrives
    from the apply environment. Omit a key entirely and Cloudflare generates one
    that it never hands back, so the dashboard becomes the only copy.
  EOT
  type = map(object({
    name                = string
    cloudflare_endpoint = string
    customer_endpoint   = optional(string)
    interface_address   = string
    interface_address6  = optional(string)
    description         = optional(string)

    replay_protection            = optional(bool)
    automatic_return_routing     = optional(bool)
    custom_remote_identity_label = optional(string)

    health_check_enabled   = optional(bool)
    health_check_direction = optional(string)
    health_check_rate      = optional(string)
    health_check_type      = optional(string)
    health_check_target    = optional(string)

    bgp_customer_asn   = optional(number)
    bgp_extra_prefixes = optional(list(string))
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.wan_ipsec_tunnels) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "wan_ipsec_tunnels keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = alltrue([
      for tunnel in var.wan_ipsec_tunnels :
      endswith(tunnel.interface_address, "/31") && can(cidrnetmask(tunnel.interface_address))
    ])
    error_message = "Each wan_ipsec_tunnels[*].interface_address must be an IPv4 /31 from private space, e.g. \"10.252.0.0/31\"."
  }

  validation {
    condition = alltrue([
      for tunnel in var.wan_ipsec_tunnels :
      tunnel.interface_address6 == null || (
        endswith(coalesce(tunnel.interface_address6, "::/0"), "/127")
        && can(cidrhost(coalesce(tunnel.interface_address6, "::/0"), 1))
      )
    ])
    error_message = "Each wan_ipsec_tunnels[*].interface_address6, when set, must be an IPv6 /127."
  }
}

variable "wan_static_routes" {
  description = <<-EOT
    The Magic routing table, keyed by a logical key: which of your prefixes
    Cloudflare reaches over which tunnel. A tunnel with no route pointing down it
    carries nothing.

    - `prefix`      - The network behind the tunnel, in CIDR notation.
    - `tunnel_key`  - A key from `wan_gre_tunnels` or `wan_ipsec_tunnels`. The
                      layer resolves the next hop from that tunnel's interface
                      address, which is the arithmetic worth not doing by hand:
                      the address in `interface_address` is Cloudflare's own side
                      of the /31, and a route pointing at it is a blackhole that
                      reads as configured in the dashboard.
    - `nexthop`     - Instead of `tunnel_key`, for a tunnel managed outside this
                      layer. Give one or the other, never both.
    - `priority`    - (Optional) Lower wins. Falls back to
                      `var.default_static_route_priority`, so two routes for one
                      prefix load-share unless you separate them.
    - `weight`      - (Optional) Relative share within an ECMP scope.
    - `description` - (Optional) Free text, shown in the dashboard.
    - `colo_names`,
      `colo_regions`- (Optional) Restrict the route to named Cloudflare colos or
                      regions. Leave both empty for a route the whole edge holds.

    Give every prefix two routes down two different tunnels. That is what makes a
    site survive one tunnel failing, and `var.allow_single_tunnel_prefixes` is
    false so the plan says so if you do not.
  EOT
  type = map(object({
    prefix       = string
    tunnel_key   = optional(string)
    nexthop      = optional(string)
    priority     = optional(number)
    weight       = optional(number)
    description  = optional(string)
    colo_names   = optional(list(string), [])
    colo_regions = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.wan_static_routes) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "wan_static_routes keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = alltrue([
      for route in var.wan_static_routes :
      length(compact([
        route.tunnel_key == null ? "" : "tunnel_key",
        route.nexthop == null ? "" : "nexthop",
      ])) == 1
    ])
    error_message = "Each wan_static_routes entry must set exactly one of tunnel_key or nexthop. tunnel_key for a tunnel this layer declares, nexthop for one managed elsewhere."
  }
}

# Secrets. Never set from a file - see the header of this file.
variable "wan_ipsec_tunnel_psks" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = <<-EOT
    IPsec pre-shared keys, keyed by the same key as var.wan_ipsec_tunnels.

    THIS VARIABLE IS NEVER SET FROM A FILE. It arrives from the pipeline as
    TF_VAR_wan_ipsec_tunnel_psks, read from the apply environment's secrets:

      TF_VAR_wan_ipsec_tunnel_psks={"london_primary":"<the psk>"}

    Three things follow, and none of them is optional reading.

    A PSK written into a .tfvars is committed the moment somebody runs
    `git add .`, and .gitignore will not save you: accounts/*/*.tfvars is
    explicitly un-ignored so account trees can be committed. CI greps committed
    tfvars for credential-shaped strings, but that is a backstop, not a control.

    The value reaches Terraform state in plain text however it is supplied,
    because Cloudflare stores it and Terraform records what it sent. State is
    therefore a credential store: it lives in R2 behind keys held in GitHub
    Environments, it is never committed, and a saved plan file is exactly as
    sensitive. Anyone holding both the PSK and the tunnel's endpoints can stand
    up the customer end of that tunnel.

    A PSK is the whole of the tunnel's authentication. Generate at least 32
    random characters per tunnel, never reuse one between tunnels or sites, and
    rotate it by updating the environment secret and re-applying - both ends at
    once, because the tunnel drops in between. Omit a tunnel's entry and
    Cloudflare generates a key it never returns, which is a reasonable choice
    where the customer end is configured by hand from the dashboard.
  EOT
}

variable "wan_bgp_md5_keys" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = <<-EOT
    BGP session keys, keyed by the same key as var.wan_gre_tunnels or
    var.wan_ipsec_tunnels. Only meaningful on a tunnel that sets
    `bgp_customer_asn`.

    Supplied the same way as the PSKs, as TF_VAR_wan_bgp_md5_keys, and for the
    same reason - it is credential-shaped and does not belong in a committed
    file.

    Do not mistake it for a security control, though. Cloudflare's own
    documentation is blunt about it: MD5 is not a valid security mechanism and
    the key is not treated as a secret. It exists to stop two devices peering by
    accident, not to stop an attacker.
  EOT
}

# Platform defaults (defaults.auto.tfvars in this directory)
variable "default_tunnel_health_check_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether tunnels run Cloudflare's health checks, for any tunnel that says
    nothing.

    This is what makes failover work. Cloudflare withdraws an unhealthy tunnel
    from the Magic routing table, so traffic moves to the next route for the
    prefix; with checks off nothing is ever withdrawn and a dead tunnel keeps
    attracting traffic until somebody notices. Declared for every tunnel rather
    than left to Cloudflare's default so that switching it off in the dashboard
    shows up as drift.
  EOT
}

variable "default_tunnel_health_check_rate" {
  type        = string
  default     = "mid"
  description = <<-EOT
    How often a tunnel is probed, for any tunnel that names nothing. One of low,
    mid, high.

    `mid` is Cloudflare's own default. `high` detects a failure sooner at the cost
    of more probe traffic, which is worth it on a metered circuit only if the
    failover is worth having.
  EOT

  validation {
    condition     = contains(["low", "mid", "high"], var.default_tunnel_health_check_rate)
    error_message = "default_tunnel_health_check_rate must be low, mid or high."
  }
}

variable "default_tunnel_health_check_type" {
  type        = string
  default     = "reply"
  description = <<-EOT
    Health check type for any tunnel that names none. One of reply, request.

    `reply` asks the far end to answer an ICMP echo, which proves the tunnel is
    up. `request` forwards the probe past the tunnel to a target address, which
    additionally proves something behind it is alive - useful where the router
    terminating the tunnel is not the thing you care about.
  EOT

  validation {
    condition     = contains(["reply", "request"], var.default_tunnel_health_check_type)
    error_message = "default_tunnel_health_check_type must be reply or request."
  }
}

variable "default_tunnel_health_check_direction" {
  type        = string
  default     = "unidirectional"
  description = <<-EOT
    Health check direction for any tunnel that names none. One of
    unidirectional, bidirectional.

    Unidirectional sends the probe through the tunnel and takes the answer back
    over the open internet, so it tests one direction and works against a device
    that will not carry the return leg. Bidirectional sends both legs through the
    tunnel, which is the honest test of the path you actually use, and needs the
    far end to route the reply back down it. Bidirectional ignores
    `health_check_target` entirely.
  EOT

  validation {
    condition     = contains(["unidirectional", "bidirectional"], var.default_tunnel_health_check_direction)
    error_message = "default_tunnel_health_check_direction must be unidirectional or bidirectional."
  }
}

variable "default_gre_tunnel_mtu" {
  type        = number
  default     = null
  description = <<-EOT
    MTU in bytes for any GRE tunnel that names none. Null leaves Cloudflare's
    default, which is 1476 - 1500 less the 24 bytes of outer IP and GRE header.

    Lower it only where the path between the two endpoints imposes something
    smaller. Getting it wrong does not break a ping; it breaks large packets
    only, which surfaces as one application being slow or hanging while
    everything else looks fine.
  EOT

  validation {
    condition     = var.default_gre_tunnel_mtu == null || (coalesce(var.default_gre_tunnel_mtu, 1476) >= 576 && coalesce(var.default_gre_tunnel_mtu, 1476) <= 1476)
    error_message = "default_gre_tunnel_mtu must be null or between 576 and 1476."
  }
}

variable "default_gre_tunnel_ttl" {
  type        = number
  default     = null
  description = "TTL in hops for any GRE tunnel that names none. Null leaves Cloudflare's default, which is what you want unless a transit provider is doing something unusual with hop counts."

  validation {
    condition     = var.default_gre_tunnel_ttl == null || (coalesce(var.default_gre_tunnel_ttl, 64) >= 1 && coalesce(var.default_gre_tunnel_ttl, 64) <= 255)
    error_message = "default_gre_tunnel_ttl must be null or between 1 and 255."
  }
}

variable "default_ipsec_replay_protection" {
  type        = bool
  default     = null
  description = <<-EOT
    IPsec anti-replay in the Cloudflare-to-customer direction, for any tunnel
    that says nothing. Null leaves Cloudflare's default.

    Replay protection rejects a duplicated ESP packet, which is the behaviour you
    want. Set it to false only for a device that cannot cope - some older or
    load-balancing middleboxes reorder enough to trip it, and the symptom is
    packet loss under load rather than a tunnel that will not come up.
  EOT
}

variable "default_automatic_return_routing" {
  type        = bool
  default     = null
  description = <<-EOT
    Stateful return routing, for any tunnel that says nothing. Null leaves
    Cloudflare's default.

    With it on, reply traffic follows the tunnel the request arrived on rather
    than needing a static route back. It makes an asymmetric estate work without
    a routing table entry per source, at the cost of the edge holding state - so
    a route in `wan_static_routes` remains the explicit, auditable answer where
    one can be written.
  EOT
}

variable "default_static_route_priority" {
  type        = number
  default     = 100
  description = <<-EOT
    Priority given to any static route that names none. Lower wins.

    Two routes for one prefix at the same priority load-share across both
    tunnels, which is the sane default for a pair of equal circuits. Give the
    standby a higher number - 200 against 100 - where one path is genuinely
    preferred.
  EOT

  validation {
    condition     = var.default_static_route_priority >= 0
    error_message = "default_static_route_priority must be zero or greater."
  }
}

# Guardrails
variable "allow_tunnels_without_health_checks" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a tunnel may have its health checks switched off.

    Health checks are what make Cloudflare withdraw a failed tunnel from the
    Magic routing table. Without them the route stays in place, traffic keeps
    being sent into a tunnel that is down, and the second tunnel you paid for
    never takes over.

    Left false, a tunnel setting `health_check_enabled = false` fails the plan
    naming it. There are real reasons to want it - a device that cannot answer
    ICMP, a bring-up window - and each of them is worth stating on a pull
    request.
  EOT
}

variable "allow_default_static_route" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a static route may carry the default route, 0.0.0.0/0 or ::/0.

    A default route in the Magic routing table sends everything Cloudflare has
    not got a more specific route for towards your network. That is occasionally
    the design - a site whose internet egress is deliberately on-premises - and is
    otherwise the single most effective way to black-hole an estate, because it
    matches every destination nobody thought about.

    Left false, the plan fails naming the route. List the prefixes you actually
    own instead.
  EOT
}

variable "allow_public_static_route_prefixes" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a static route's prefix may sit outside private address space.

    Cloudflare WAN routes traffic between your own sites, so its prefixes are
    RFC 1918, RFC 6598 or IPv6 unique-local. A public prefix here means one of
    three things: a typo, an attempt to attract address space the account does
    not own, or Magic Transit - which advertises your public prefixes through
    Cloudflare, is a different product, and is out of scope for this layer.

    Left false, the plan fails naming the route. The default route has its own
    gate, `allow_default_static_route`, and is not reported twice.
  EOT
}

variable "allow_single_tunnel_prefixes" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a prefix may be reachable over exactly one tunnel.

    One tunnel is a single point of failure with a health check attached: the
    check notices the failure, and there is nowhere for the traffic to go.
    Cloudflare's own guidance is at least two tunnels per site, on separate
    circuits or at least separate devices, and four where the site matters.

    Left false, the plan fails listing each prefix with only one route. Set it
    true for a lab, a pilot site, or a first-tunnel bring-up where the second is
    a known follow-up.
  EOT
}

variable "allow_static_routes_to_unmanaged_nexthops" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a static route may name a `nexthop` that belongs to no tunnel this
    layer declares.

    The usual cause is a hand-written next hop that is one address out - the
    Cloudflare side of the /31 instead of the customer side, or a neighbouring
    tunnel's. Cloudflare accepts any address, the dashboard shows the route as
    configured, and the traffic is discarded silently. That is why `tunnel_key`
    exists: it derives the address from the tunnel.

    Left false, the plan fails naming the route. Set it true where the tunnel
    genuinely lives elsewhere - a Cloudflare Network Interconnect, or a tunnel
    another team owns.
  EOT
}
