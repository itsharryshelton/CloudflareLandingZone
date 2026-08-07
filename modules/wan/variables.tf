variable "account_id" {
  type        = string
  description = <<-EOT
    Cloudflare Account ID. Cloudflare WAN tunnels and static routes are
    account-scoped: no zone is involved anywhere in this module.

    Cloudflare WAN (formerly Magic WAN) is an Enterprise product and is enabled
    on the account by Cloudflare when it is bought. Nothing here turns it on, and
    there is no resource that could - an account without the entitlement answers
    every call below with an authorisation error rather than a quota message.
  EOT

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

# GRE tunnels
variable "gre_tunnels" {
  type = list(object({
    name                     = string
    cloudflare_endpoint      = string
    customer_endpoint        = string
    interface_address        = string
    interface_address6       = optional(string)
    description              = optional(string)
    mtu                      = optional(number)
    ttl                      = optional(number)
    automatic_return_routing = optional(bool)

    health_check = optional(object({
      enabled   = optional(bool)
      direction = optional(string)
      rate      = optional(string)
      type      = optional(string)
      target    = optional(string)
    }))

    bgp = optional(object({
      customer_asn   = number
      extra_prefixes = optional(list(string))
      md5_key        = optional(string)
    }))
  }))
  default     = []
  description = <<-EOT
    GRE tunnels from a customer device to Cloudflare's edge. GRE is plaintext:
    it encapsulates, it does not encrypt. Use it over a private circuit, and use
    an `ipsec_tunnels` entry over the public internet.

      - name                    : the tunnel's identity in Cloudflare. Unique
                                  across every tunnel on the account, GRE and
                                  IPsec alike, and renaming one destroys and
                                  recreates it - which drops the traffic on it.
      - cloudflare_endpoint     : the anycast IP Cloudflare allocated to the
                                  account. Not something you choose.
      - customer_endpoint       : the public IP of the device at your end.
      - interface_address       : the /31 the tunnel is numbered from. The
                                  address you write is Cloudflare's side; the
                                  other host in the /31 is the customer device's,
                                  and that is what a static route's next hop has
                                  to be.
      - interface_address6      : (optional) the equivalent /127, for a tunnel
                                  that also carries IPv6.
      - description             : free text, shown in the dashboard.
      - mtu                     : bytes. Cloudflare's GRE MTU is 1476, which is
                                  1500 less the 24 bytes of outer IP and GRE
                                  header. Leave it unset unless the path in
                                  between imposes something lower.
      - ttl                     : hops. Leave unset for Cloudflare's default.
      - automatic_return_routing: stateful return routing, so reply traffic
                                  follows the tunnel it arrived on without a
                                  matching static route.
      - health_check            : see the description of the field on
                                  ipsec_tunnels. A tunnel whose health check is
                                  off is never withdrawn from the Magic routing
                                  table, so traffic keeps being sent into a dead
                                  tunnel.
      - bgp                     : dynamic routing instead of static routes.
                                  `customer_asn` is the ASN on your device,
                                  `extra_prefixes` are advertised to it on top of
                                  the Magic routing table, and `md5_key` is a
                                  session key. Cloudflare's own documentation says
                                  the MD5 key is not a security measure and is not
                                  treated as a secret; it prevents
                                  misconfiguration, not attack.
  EOT

  validation {
    condition     = alltrue([for tunnel in var.gre_tunnels : can(regex("^[A-Za-z0-9_-]{1,15}$", tunnel.name))])
    error_message = "Each gre_tunnels[*].name must be 1-15 characters of letters, numbers, underscores or hyphens. Cloudflare rejects spaces and punctuation, and caps a tunnel name at 15 characters."
  }

  validation {
    condition     = alltrue([for tunnel in var.gre_tunnels : can(cidrnetmask("${tunnel.cloudflare_endpoint}/32"))])
    error_message = "Each gre_tunnels[*].cloudflare_endpoint must be a bare IPv4 address, with no prefix length - it is one of the anycast addresses Cloudflare allocated to the account."
  }

  validation {
    condition     = alltrue([for tunnel in var.gre_tunnels : can(cidrnetmask("${tunnel.customer_endpoint}/32"))])
    error_message = "Each gre_tunnels[*].customer_endpoint must be a bare IPv4 address, with no prefix length."
  }

  validation {
    condition = alltrue([
      for tunnel in var.gre_tunnels :
      endswith(tunnel.interface_address, "/31") && can(cidrnetmask(tunnel.interface_address))
    ])
    error_message = "Each gre_tunnels[*].interface_address must be an IPv4 /31, e.g. \"10.252.0.0/31\". Cloudflare numbers a tunnel from a two-host subnet: one address for its side, one for yours."
  }

  validation {
    condition = alltrue([
      for tunnel in var.gre_tunnels :
      can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.)", tunnel.interface_address))
    ])
    error_message = "Each gre_tunnels[*].interface_address must come from private space: 10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16. Cloudflare requires it, and numbering a tunnel from public space means your device answers for an address somebody else owns."
  }

  validation {
    condition = alltrue([
      for tunnel in var.gre_tunnels :
      tunnel.interface_address6 == null || (
        endswith(coalesce(tunnel.interface_address6, "::/0"), "/127")
        && can(cidrhost(coalesce(tunnel.interface_address6, "::/0"), 1))
      )
    ])
    error_message = "Each gre_tunnels[*].interface_address6, when set, must be an IPv6 /127 taken from the tunnel's virtual_subnet6 space."
  }

  validation {
    condition     = alltrue([for tunnel in var.gre_tunnels : tunnel.mtu == null || (coalesce(tunnel.mtu, 1476) >= 576 && coalesce(tunnel.mtu, 1476) <= 1476)])
    error_message = "Each gre_tunnels[*].mtu, when set, must be between 576 and 1476. 1476 is 1500 less the outer IP and GRE headers, which is the most a GRE tunnel over a standard 1500-byte path can carry."
  }

  validation {
    condition     = alltrue([for tunnel in var.gre_tunnels : tunnel.ttl == null || (coalesce(tunnel.ttl, 64) >= 1 && coalesce(tunnel.ttl, 64) <= 255)])
    error_message = "Each gre_tunnels[*].ttl, when set, must be between 1 and 255."
  }

  validation {
    condition = alltrue([
      for tunnel in var.gre_tunnels :
      tunnel.health_check == null || contains(["unidirectional", "bidirectional", ""], coalesce(try(tunnel.health_check.direction, ""), ""))
    ])
    error_message = "Each gre_tunnels[*].health_check.direction, when set, must be \"unidirectional\" or \"bidirectional\"."
  }

  validation {
    condition = alltrue([
      for tunnel in var.gre_tunnels :
      tunnel.health_check == null || contains(["low", "mid", "high", ""], coalesce(try(tunnel.health_check.rate, ""), ""))
    ])
    error_message = "Each gre_tunnels[*].health_check.rate, when set, must be \"low\", \"mid\" or \"high\"."
  }

  validation {
    condition = alltrue([
      for tunnel in var.gre_tunnels :
      tunnel.health_check == null || contains(["reply", "request", ""], coalesce(try(tunnel.health_check.type, ""), ""))
    ])
    error_message = "Each gre_tunnels[*].health_check.type, when set, must be \"reply\" or \"request\"."
  }

  validation {
    condition = alltrue([
      for tunnel in var.gre_tunnels :
      tunnel.bgp == null || (coalesce(try(tunnel.bgp.customer_asn, 1), 1) >= 1 && coalesce(try(tunnel.bgp.customer_asn, 1), 1) <= 4294967295)
    ])
    error_message = "Each gre_tunnels[*].bgp.customer_asn must be a valid 32-bit ASN, between 1 and 4294967295."
  }

  validation {
    condition = alltrue([
      for tunnel in var.gre_tunnels :
      tunnel.bgp == null || try(tunnel.bgp.md5_key, null) == null || can(regex("^[^\"?\\t\\n\\r\\v\\f]+$", coalesce(try(tunnel.bgp.md5_key, ""), "")))
    ])
    error_message = "Each gre_tunnels[*].bgp.md5_key, when set, must be non-empty printable ASCII without a quotation mark, question mark or whitespace control character. Cloudflare rejects the rest."
  }
}

# IPsec tunnels
variable "ipsec_tunnels" {
  type = list(object({
    name                         = string
    cloudflare_endpoint          = string
    customer_endpoint            = optional(string)
    interface_address            = string
    interface_address6           = optional(string)
    description                  = optional(string)
    psk                          = optional(string)
    replay_protection            = optional(bool)
    automatic_return_routing     = optional(bool)
    custom_remote_identity_label = optional(string)

    health_check = optional(object({
      enabled   = optional(bool)
      direction = optional(string)
      rate      = optional(string)
      type      = optional(string)
      target    = optional(string)
    }))

    bgp = optional(object({
      customer_asn   = number
      extra_prefixes = optional(list(string))
      md5_key        = optional(string)
    }))
  }))
  default     = []
  description = <<-EOT
    IPsec tunnels - the site-to-site option, and the right one over the public
    internet, because unlike GRE the payload is encrypted.

      - name                        : the tunnel's identity in Cloudflare, unique
                                      across every tunnel on the account,
                                      IPsec and GRE alike.
      - cloudflare_endpoint         : the anycast IP Cloudflare allocated to the
                                      account.
      - customer_endpoint           : (optional) the public IP of your device.
                                      Cloudflare does not need it to bring the
                                      tunnel up, because the customer end always
                                      initiates, but proactive traceroutes do not
                                      work without it. Leave it unset for a device
                                      behind a dynamic address.
      - interface_address           : the /31 the tunnel is numbered from. The
                                      address written is Cloudflare's side.
      - interface_address6          : (optional) the equivalent /127.
      - description                 : free text, shown in the dashboard.
      - psk                         : the pre-shared key. SEE BELOW - this is a
                                      credential, and it does not belong in a
                                      file.
      - replay_protection           : IPsec anti-replay in the
                                      Cloudflare-to-customer direction. Leave
                                      unset for Cloudflare's default; some older
                                      devices cannot cope with it.
      - automatic_return_routing    : stateful return routing, so reply traffic
                                      follows the tunnel it arrived on without a
                                      matching static route.
      - custom_remote_identity_label: (optional) a label for a custom IKE ID of
                                      type FQDN. The module builds the full
                                      `<label>.<account id>.custom.ipsec.cloudflare.com`
                                      identity, which is the part that is easy to
                                      mistype by hand. Needed where the device at
                                      your end cannot present the generated IKE ID.
      - health_check                : `enabled`, `direction`
                                      (unidirectional or bidirectional), `rate`
                                      (low, mid, high), `type` (reply or request)
                                      and `target`, the address a request-type
                                      check is forwarded to after the tunnel
                                      decapsulates it. A bidirectional check
                                      ignores `target` entirely.
      - bgp                         : dynamic routing instead of static routes,
                                      as on gre_tunnels.

    ON THE PSK. Terraform records what it sends, so a PSK reaches state in plain
    text however it is supplied. It must therefore never be written into a
    `.tfvars` file - it arrives from the deployment's environment. See the
    `wan_ipsec_tunnel_psks` variable in layers/wan for how that is wired.

    Leave `psk` unset and Cloudflare generates one at creation. That is a real
    option, and often the better one, but understand the trade: the generated
    value is not returned to Terraform, so the only place to read it is the
    Cloudflare dashboard, and the device at the other end has to be configured
    from there by hand.
  EOT

  validation {
    condition     = alltrue([for tunnel in var.ipsec_tunnels : can(regex("^[A-Za-z0-9_-]{1,15}$", tunnel.name))])
    error_message = "Each ipsec_tunnels[*].name must be 1-15 characters of letters, numbers, underscores or hyphens. Cloudflare rejects spaces and punctuation, and the 15-character cap it documents for GRE applies here too - tunnel names share one namespace."
  }

  validation {
    condition     = alltrue([for tunnel in var.ipsec_tunnels : can(cidrnetmask("${tunnel.cloudflare_endpoint}/32"))])
    error_message = "Each ipsec_tunnels[*].cloudflare_endpoint must be a bare IPv4 address, with no prefix length - it is one of the anycast addresses Cloudflare allocated to the account."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      tunnel.customer_endpoint == null || can(cidrnetmask("${coalesce(tunnel.customer_endpoint, "0.0.0.0")}/32"))
    ])
    error_message = "Each ipsec_tunnels[*].customer_endpoint, when set, must be a bare IPv4 address, with no prefix length."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      endswith(tunnel.interface_address, "/31") && can(cidrnetmask(tunnel.interface_address))
    ])
    error_message = "Each ipsec_tunnels[*].interface_address must be an IPv4 /31, e.g. \"10.252.0.0/31\"."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.)", tunnel.interface_address))
    ])
    error_message = "Each ipsec_tunnels[*].interface_address must come from private space: 10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      tunnel.interface_address6 == null || (
        endswith(coalesce(tunnel.interface_address6, "::/0"), "/127")
        && can(cidrhost(coalesce(tunnel.interface_address6, "::/0"), 1))
      )
    ])
    error_message = "Each ipsec_tunnels[*].interface_address6, when set, must be an IPv6 /127 taken from the tunnel's virtual_subnet6 space."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      tunnel.psk == null || length(coalesce(tunnel.psk, "")) >= 16
    ])
    error_message = "Each ipsec_tunnels[*].psk, when set, must be at least 16 characters. A short pre-shared key is brute-forceable offline from a single captured IKE exchange; 32 or more random characters is the sane length. Leave psk unset to have Cloudflare generate one instead."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      tunnel.custom_remote_identity_label == null || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", coalesce(tunnel.custom_remote_identity_label, "")))
    ])
    error_message = "Each ipsec_tunnels[*].custom_remote_identity_label must be a single DNS label: lowercase letters, numbers and hyphens, not starting or ending with a hyphen. The module appends the account and Cloudflare's suffix to it."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      tunnel.health_check == null || contains(["unidirectional", "bidirectional", ""], coalesce(try(tunnel.health_check.direction, ""), ""))
    ])
    error_message = "Each ipsec_tunnels[*].health_check.direction, when set, must be \"unidirectional\" or \"bidirectional\"."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      tunnel.health_check == null || contains(["low", "mid", "high", ""], coalesce(try(tunnel.health_check.rate, ""), ""))
    ])
    error_message = "Each ipsec_tunnels[*].health_check.rate, when set, must be \"low\", \"mid\" or \"high\"."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      tunnel.health_check == null || contains(["reply", "request", ""], coalesce(try(tunnel.health_check.type, ""), ""))
    ])
    error_message = "Each ipsec_tunnels[*].health_check.type, when set, must be \"reply\" or \"request\"."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      tunnel.bgp == null || (coalesce(try(tunnel.bgp.customer_asn, 1), 1) >= 1 && coalesce(try(tunnel.bgp.customer_asn, 1), 1) <= 4294967295)
    ])
    error_message = "Each ipsec_tunnels[*].bgp.customer_asn must be a valid 32-bit ASN, between 1 and 4294967295."
  }

  validation {
    condition = alltrue([
      for tunnel in var.ipsec_tunnels :
      tunnel.bgp == null || try(tunnel.bgp.md5_key, null) == null || can(regex("^[^\"?\\t\\n\\r\\v\\f]+$", coalesce(try(tunnel.bgp.md5_key, ""), "")))
    ])
    error_message = "Each ipsec_tunnels[*].bgp.md5_key, when set, must be non-empty printable ASCII without a quotation mark, question mark or whitespace control character. Cloudflare rejects the rest."
  }
}

# Static routes
variable "static_routes" {
  type = list(object({
    prefix       = string
    priority     = number
    nexthop      = optional(string)
    tunnel_name  = optional(string)
    weight       = optional(number)
    description  = optional(string)
    colo_names   = optional(list(string), [])
    colo_regions = optional(list(string), [])
  }))
  default     = []
  description = <<-EOT
    The Magic routing table: which of your prefixes Cloudflare reaches over which
    tunnel. A tunnel with no route pointing down it carries nothing.

      - prefix      : the network behind the tunnel, in CIDR notation. IPv4 or
                      IPv6.
      - priority    : lower wins. Give a site's tunnels different priorities for
                      active/standby, or the same priority for ECMP across both.
      - nexthop     : the customer-side address of the tunnel. Give this OR
                      `tunnel_name`, not both.
      - tunnel_name : name of a tunnel declared in `gre_tunnels` or
                      `ipsec_tunnels`. The module derives the next hop from that
                      tunnel's interface address, which is the arithmetic worth
                      not doing by hand: the address written in
                      `interface_address` is Cloudflare's own side of the /31, and
                      a route pointing at it is a blackhole that looks correct in
                      the dashboard.
      - weight      : relative share of an ECMP set. Only meaningful with a scope.
      - description : free text, shown in the dashboard.
      - colo_names  : restrict the route to named Cloudflare colos.
      - colo_regions: restrict the route to Cloudflare regions.

    Two routes for the same prefix down two different tunnels is the normal
    shape - it is what makes a site survive one tunnel failing.
  EOT

  validation {
    condition     = alltrue([for route in var.static_routes : can(cidrhost(route.prefix, 0))])
    error_message = "Each static_routes[*].prefix must be a valid CIDR block, e.g. \"10.10.0.0/16\" or \"2001:db8::/48\". A bare address with no prefix length is rejected."
  }

  validation {
    condition     = alltrue([for route in var.static_routes : route.priority >= 0])
    error_message = "Each static_routes[*].priority must be zero or greater. Lower priorities are preferred, so 100 and 200 is the usual way to write primary and standby."
  }

  validation {
    condition = alltrue([
      for route in var.static_routes :
      length(compact([
        route.nexthop == null ? "" : "nexthop",
        route.tunnel_name == null ? "" : "tunnel_name",
      ])) == 1
    ])
    error_message = "Each static_routes entry must set exactly one of nexthop or tunnel_name. tunnel_name for a tunnel this module declares, nexthop for anything else."
  }

  validation {
    condition = alltrue([
      for route in var.static_routes :
      route.nexthop == null
      || can(cidrnetmask("${coalesce(route.nexthop, "0.0.0.0")}/32"))
      || can(cidrhost("${coalesce(route.nexthop, "::")}/128", 0))
    ])
    error_message = "Each static_routes[*].nexthop, when set, must be a bare IP address with no prefix length."
  }

  validation {
    condition     = alltrue([for route in var.static_routes : route.weight == null || coalesce(route.weight, 1) >= 1])
    error_message = "Each static_routes[*].weight, when set, must be at least 1."
  }
}
