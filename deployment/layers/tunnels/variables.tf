# Layer tunnels - inputs.
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/zones.tfvars   - the zone inventory, for public hostnames
#   accounts/<account>/tunnels.tfvars - tunnels, virtual networks and routes

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Tunnels, routes and virtual networks are account-scoped resources."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: logical key => domain name. The same file the zones layer is
    given, so the keys mean the same thing in both.

    This layer does not create zones. It looks up only the zones a public
    hostname actually references, to get their IDs (see zone_lookup.tf), which
    keeps the two layers' states independent.

    - `domain_name` - The apex domain (e.g. example.com).
    - `zone_tier`   - (Optional) Unused here, and declared only so that the shared
                      inventory file can carry it for the layers that do gate on
                      it. Terraform rejects a .tfvars attribute the variable type
                      does not declare.
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

variable "cloudflare_tunnels" {
  description = <<-EOT
    Cloudflare Tunnels, keyed by a logical key. Routes refer to a tunnel by that
    key.

    The key is a handle. The `name` is identity: changing it destroys and
    recreates the tunnel, which issues a new tunnel ID and token and disconnects
    every connector running the old one.

    - `name`              - Display name in the dashboard. Unique on the account.
    - `config_src`        - (Optional) "cloudflare" - remotely managed, and the
                            ingress rules below are pushed to every connector - or
                            "local", where the connector reads config.yml on its
                            own host and `ingress` must be empty. Falls back to
                            var.default_tunnel_config_src. Changing it replaces the
                            tunnel.
    - `ingress`           - (Optional) Public hostnames, IN EVALUATION ORDER. The
                            first rule that matches a request decides, so a
                            path-specific rule must come before the bare hostname
                            it narrows. Each rule is:
                              `hostname`       - the public hostname, for example
                                                 "grafana.example.com". A leading
                                                 "*." publishes every subdomain.
                              `zone_key`       - a key from zones.tfvars. The layer
                                                 creates the proxied CNAME pointing
                                                 the hostname at the tunnel, in that
                                                 zone. Leave it out only for a
                                                 hostname whose DNS lives elsewhere -
                                                 see var.allow_unmanaged_tunnel_hostnames.
                                                 Do not also declare the record in
                                                 dns.tfvars: Cloudflare refuses a
                                                 second record of the same name.
                              `path`           - (Optional) A regular expression the
                                                 request path must match.
                              `service`        - Where cloudflared sends the request:
                                                 http://, https://, tcp://, ssh://,
                                                 rdp://, smb://, unix://, unix+tls://,
                                                 or http_status:<code>.
                              `origin_request` - (Optional) Connection settings for
                                                 this rule, overriding the tunnel-wide
                                                 ones below.
                            A catch-all rule answering `catch_all_service` is
                            appended after the last rule. Do not write one.
    - `catch_all_service` - (Optional) What a request matching no rule gets. Falls
                            back to var.default_catch_all_service.
    - `origin_request`    - (Optional) Tunnel-wide settings for the connection
                            between cloudflared and the origin:
                              `access`             - { team_name, aud_tags, required }.
                                                     cloudflared validates the Access
                                                     token on every request itself, so
                                                     a request that reached the tunnel
                                                     without passing Access is refused.
                                                     `aud_tags` are Access application
                                                     AUD tags - the zerotrust layer's
                                                     access_applications output.
                                                     `required` defaults to true.
                              `no_tls_verify`      - Accept any certificate the origin
                                                     presents. Restricted - see
                                                     var.allow_no_tls_verify.
                              `origin_server_name` - The name the origin certificate is
                                                     checked against, where it differs
                                                     from the service host.
                              `ca_pool`            - Path on the connector host to a CA
                                                     bundle, for a privately signed
                                                     origin certificate.
                              `http_host_header`, `http2_origin`, `connect_timeout`,
                              `tls_timeout`, `tcp_keep_alive`, `keep_alive_connections`,
                              `keep_alive_timeout`, `disable_chunked_encoding`,
                              `no_happy_eyeballs`, `match_sni_to_host`, `proxy_type`
                                                   - As cloudflared documents them.
                                                     Timeouts are in seconds.

    A public hostname is reachable by anybody on the internet unless an Access
    application in the zerotrust layer covers it. This layer cannot see that
    layer's state, so it cannot check. Pair every hostname here with an
    application there, and set `access` so the origin enforces it too.

    Redundancy is more connectors on one tunnel, not more tunnels: run cloudflared
    with the same token on two hosts and Cloudflare balances across them.
  EOT
  type = map(object({
    name              = string
    config_src        = optional(string)
    catch_all_service = optional(string)
    origin_request = optional(object({
      access = optional(object({
        team_name = string
        aud_tags  = list(string)
        required  = optional(bool, true)
      }))
      ca_pool                  = optional(string)
      connect_timeout          = optional(number)
      disable_chunked_encoding = optional(bool)
      http2_origin             = optional(bool)
      http_host_header         = optional(string)
      keep_alive_connections   = optional(number)
      keep_alive_timeout       = optional(number)
      match_sni_to_host        = optional(bool)
      no_happy_eyeballs        = optional(bool)
      no_tls_verify            = optional(bool)
      origin_server_name       = optional(string)
      proxy_type               = optional(string)
      tcp_keep_alive           = optional(number)
      tls_timeout              = optional(number)
    }))
    ingress = optional(list(object({
      hostname = string
      zone_key = optional(string)
      path     = optional(string)
      service  = string
      origin_request = optional(object({
        access = optional(object({
          team_name = string
          aud_tags  = list(string)
          required  = optional(bool, true)
        }))
        ca_pool                  = optional(string)
        connect_timeout          = optional(number)
        disable_chunked_encoding = optional(bool)
        http2_origin             = optional(bool)
        http_host_header         = optional(string)
        keep_alive_connections   = optional(number)
        keep_alive_timeout       = optional(number)
        match_sni_to_host        = optional(bool)
        no_happy_eyeballs        = optional(bool)
        no_tls_verify            = optional(bool)
        origin_server_name       = optional(string)
        proxy_type               = optional(string)
        tcp_keep_alive           = optional(number)
        tls_timeout              = optional(number)
      }))
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.cloudflare_tunnels) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "cloudflare_tunnels keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for tunnel in var.cloudflare_tunnels : lower(trimspace(tunnel.name))
    ])) == length(var.cloudflare_tunnels)
    error_message = "Two cloudflare_tunnels entries share a name. The name is the tunnel's identity in Cloudflare, so each must be uniquely named."
  }
}

variable "tunnel_virtual_networks" {
  description = <<-EOT
    Virtual networks, keyed by a logical key. A virtual network is a separate
    private routing table, so two sites that both number themselves
    172.16.0.0/16 can each be reached without their routes colliding.

    Every account already has one named "default", and a route that names no
    virtual network lands in it. Declare more only where address space
    genuinely overlaps.

    - `name`               - Identity in Cloudflare. Renaming destroys and
                             recreates it, and every route scoped to it with it.
    - `comment`            - (Optional) Free text.
    - `is_default_network` - (Optional) Make this the network a WARP client uses
                             unless its profile says otherwise. At most one, and
                             think before setting it: taking the role from the
                             built-in network changes where every unscoped route
                             resolves, for every user at once.
  EOT
  type = map(object({
    name               = string
    comment            = optional(string)
    is_default_network = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.tunnel_virtual_networks) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "tunnel_virtual_networks keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition = length(distinct([
      for network in var.tunnel_virtual_networks : lower(trimspace(network.name))
    ])) == length(var.tunnel_virtual_networks)
    error_message = "Two tunnel_virtual_networks entries share a name. Each virtual network must be uniquely named."
  }
}

variable "tunnel_routes" {
  description = <<-EOT
    Private network routes, keyed by a logical key: which address ranges a WARP
    client reaches through which tunnel.

    - `network`             - The range behind the tunnel, in CIDR notation.
    - `tunnel_key`          - A key from var.cloudflare_tunnels.
    - `virtual_network_key` - (Optional) A key from var.tunnel_virtual_networks.
    - `virtual_network_id`  - (Optional) The same, for a virtual network managed
                              outside this layer. Give at most one of the two;
                              neither means the account's default.
    - `comment`             - (Optional) Free text, up to 100 characters.

    A route makes a range reachable by the device, not by the person. Who may
    reach what inside it is a Gateway network policy or an Access application
    with a private destination - neither of which lives in this layer.
  EOT
  type = map(object({
    network             = string
    tunnel_key          = string
    virtual_network_key = optional(string)
    virtual_network_id  = optional(string)
    comment             = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.tunnel_routes) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "tunnel_routes keys must be lowercase alphanumeric with underscores - they become Terraform resource addresses and state keys."
  }

  validation {
    condition     = alltrue([for route in var.tunnel_routes : route.virtual_network_key == null || route.virtual_network_id == null])
    error_message = "A tunnel_routes entry sets both virtual_network_key and virtual_network_id. Give the key for a virtual network this layer declares, the ID for one managed elsewhere, or neither for the account's default."
  }
}

# Platform defaults (defaults.auto.tfvars)
variable "default_tunnel_config_src" {
  type        = string
  default     = "cloudflare"
  description = <<-EOT
    Configuration source for a tunnel that names none. "cloudflare" makes the
    ingress rules in this repository the ones every connector runs, and turns a
    hand edit in the dashboard into drift on the next plan. "local" leaves the
    rules in config.yml on each connector host, out of sight of this layer.
  EOT

  validation {
    condition     = contains(["cloudflare", "local"], var.default_tunnel_config_src)
    error_message = "default_tunnel_config_src must be \"cloudflare\" or \"local\"."
  }
}

variable "default_catch_all_service" {
  type        = string
  default     = "http_status:404"
  description = <<-EOT
    What a request that matches no ingress rule gets, for a tunnel that names
    nothing. A 404 is the safe answer: sending unmatched requests to a real
    service publishes it on every hostname the tunnel answers, including ones
    nobody meant to route to it.
  EOT

  validation {
    condition     = can(regex("^((https?|tcp|ssh|rdp|smb|unix|unix\\+tls)://\\S+|http_status:[1-5][0-9]{2})$", trimspace(var.default_catch_all_service)))
    error_message = "default_catch_all_service must be http_status:<code>, e.g. \"http_status:404\", or a service URL."
  }
}

# Guardrails
variable "allow_no_tls_verify" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether an origin_request may set `no_tls_verify = true`.

    It makes cloudflared accept any certificate the origin presents, so the hop
    between connector and origin is encrypted but not authenticated - anything
    able to answer on that address is trusted. The usual reason is a
    self-signed origin certificate, and the fix for that is `ca_pool` or
    `origin_server_name`, not switching verification off.

    Left false, the plan fails naming each rule that sets it.
  EOT
}

variable "allow_unmanaged_tunnel_hostnames" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether an ingress rule may omit `zone_key`, leaving its DNS record to be
    created somewhere else.

    Without a record the hostname never reaches the tunnel, and nothing in the
    dashboard says so - the rule looks configured. Left false, the plan fails
    naming each rule without one. Set it true where a hostname's zone is on
    another account or its DNS is genuinely managed elsewhere.
  EOT
}

variable "allow_default_tunnel_route" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a tunnel route may carry the default route, 0.0.0.0/0 or ::/0.

    That sends every destination WARP has no more specific route for down one
    connector, making that site the internet egress for every enrolled device -
    and a single connector host a single point of failure for all of it. Left
    false, the plan fails naming the route. List the ranges the site actually
    owns instead.
  EOT
}

variable "allow_public_tunnel_route_prefixes" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a tunnel route's range may sit outside private address space.

    A private network route is for RFC 1918, RFC 6598 or IPv6 unique-local
    ranges. A public range here pulls traffic for somebody else's address space
    down a connector, which is either a typo or an egress design that deserves
    its own pull request. Left false, the plan fails naming the route. The
    default route has its own gate, allow_default_tunnel_route, and is not
    reported twice.
  EOT
}
