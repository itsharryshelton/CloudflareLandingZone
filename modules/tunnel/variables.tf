variable "account_id" {
  type        = string
  description = <<-EOT
    Cloudflare Account ID. Tunnels, their routes and virtual networks are
    account-scoped; a zone appears only as the zone_id of a public hostname's
    DNS record.
  EOT

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "tunnels" {
  type = list(object({
    name              = string
    config_src        = optional(string, "cloudflare")
    catch_all_service = optional(string, "http_status:404")
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
      path     = optional(string)
      service  = string
      zone_id  = optional(string)
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
  default     = []
  description = <<-EOT
    Cloudflare Tunnels: outbound-only connectors that publish origins on a
    private network without opening an inbound port.

      - name              : the tunnel's identity here and in Cloudflare, matched
                            lower-cased and trimmed. Renaming destroys and
                            recreates the tunnel, which issues a new ID and token
                            and disconnects every connector running the old one.
      - config_src        : "cloudflare" (default) - remotely managed, and the
                            ingress rules below are pushed to every connector - or
                            "local", where the connector reads config.yml on its
                            own host and `ingress` must be empty. Changing it
                            replaces the tunnel.
      - catch_all_service : what a request matching no rule gets. Appended as the
                            final rule, which cloudflared requires. Defaults to
                            "http_status:404".
      - origin_request    : tunnel-wide connection settings between cloudflared
                            and the origin. A rule's own origin_request overrides
                            it. `access` makes cloudflared validate the Access JWT
                            itself: `team_name` is the Zero Trust team, `aud_tags`
                            the Access applications allowed through, and `required`
                            (default true) refuses any request without one.
                            `match_sni_to_host` is the provider's
                            `match_sn_ito_host`, renamed here to what it does.
                            Timeouts are in seconds.
      - ingress           : public hostnames, in evaluation order - the first rule
                            that matches decides. Each rule is:
                              hostname       - the public hostname. A leading "*."
                                               publishes every subdomain.
                              path           - (optional) a regular expression the
                                               request path must match.
                              service        - http://, https://, tcp://, ssh://,
                                               rdp://, smb://, unix://, unix+tls://,
                                               or http_status:<code>.
                              zone_id        - (optional) the zone to create the
                                               hostname's proxied CNAME in. Leave it
                                               unset for a hostname whose DNS is
                                               managed elsewhere.
                              origin_request - (optional) as above, for this rule.

    No tunnel secret is sent. Cloudflare generates one and never returns it, so
    Terraform state holds nothing that can run a connector. Fetch the token when
    installing a connector: dashboard, `cloudflared tunnel token <id>`, or
    GET /accounts/<account_id>/cfd_tunnel/<tunnel_id>/token.
  EOT

  validation {
    condition     = alltrue([for tunnel in var.tunnels : trimspace(tunnel.name) != ""])
    error_message = "Each tunnels[*].name must be a non-empty display name."
  }

  validation {
    condition = length(distinct([
      for tunnel in var.tunnels : lower(trimspace(tunnel.name))
    ])) == length(var.tunnels)
    error_message = "tunnels contains duplicate names. Names are compared lower-cased and trimmed, and they are how a route refers to a tunnel - each tunnel must be uniquely named."
  }

  validation {
    condition     = alltrue([for tunnel in var.tunnels : contains(["cloudflare", "local"], tunnel.config_src)])
    error_message = "Each tunnels[*].config_src must be \"cloudflare\" (remotely managed) or \"local\" (config.yml on the connector host)."
  }

  # A locally managed connector never reads remote configuration, so rules given
  # for one would be accepted, shown in the dashboard, and ignored.
  validation {
    condition     = alltrue([for tunnel in var.tunnels : tunnel.config_src == "cloudflare" || length(tunnel.ingress) == 0])
    error_message = "A tunnels[*] entry with config_src = \"local\" has ingress rules. A locally managed connector takes its rules from config.yml on its own host and ignores these. Remove them, or make the tunnel remotely managed."
  }

  # Inlined in both checks below rather than held in a local: variable
  # validation cannot reference locals.
  validation {
    condition = alltrue([
      for tunnel in var.tunnels :
      can(regex("^((https?|tcp|ssh|rdp|smb|unix|unix\\+tls)://\\S+|http_status:[1-5][0-9]{2})$", trimspace(tunnel.catch_all_service)))
    ])
    error_message = "Each tunnels[*].catch_all_service must be http_status:<code>, e.g. \"http_status:404\", or a service URL."
  }

  validation {
    condition = alltrue(flatten([
      for tunnel in var.tunnels : [
        for rule in tunnel.ingress :
        can(regex("^((https?|tcp|ssh|rdp|smb|unix|unix\\+tls)://\\S+|http_status:[1-5][0-9]{2})$", trimspace(rule.service)))
      ]
    ]))
    error_message = "Each tunnels[*].ingress[*].service must be a URL using http, https, tcp, ssh, rdp, smb, unix or unix+tls - e.g. \"http://localhost:8080\" - or http_status:<code>."
  }

  validation {
    condition = alltrue(flatten([
      for tunnel in var.tunnels : [
        for rule in tunnel.ingress :
        can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", lower(trimspace(rule.hostname))))
      ]
    ]))
    error_message = "Each tunnels[*].ingress[*].hostname must be a fully-qualified hostname such as \"app.example.com\", optionally starting \"*.\". No scheme, no port, no path - a path belongs in `path`."
  }

  # The second of two identical rules can never match, so it is either a copy or
  # a rule that was meant to differ and does not.
  validation {
    condition = alltrue([
      for tunnel in var.tunnels :
      length(distinct([
        for rule in tunnel.ingress : "${lower(trimspace(rule.hostname))}|${rule.path == null ? "" : rule.path}"
      ])) == length(tunnel.ingress)
    ])
    error_message = "A tunnels[*].ingress list repeats a hostname and path pair. cloudflared stops at the first match, so the second rule is unreachable."
  }

  # One hostname has one CNAME, and a CNAME points at one tunnel.
  validation {
    condition = length(flatten([
      for tunnel in var.tunnels : distinct([for rule in tunnel.ingress : lower(trimspace(rule.hostname))])
      ])) == length(distinct(flatten([
        for tunnel in var.tunnels : [for rule in tunnel.ingress : lower(trimspace(rule.hostname))]
    ])))
    error_message = "The same ingress hostname appears in more than one tunnel. A hostname's DNS record can point at only one tunnel, so the other tunnel's rules would never see a request. Run more connectors for the one tunnel instead - that is how cloudflared is made redundant."
  }

  validation {
    condition = alltrue(flatten([
      for tunnel in var.tunnels : [
        for hostname in distinct([for rule in tunnel.ingress : lower(trimspace(rule.hostname))]) :
        length(distinct([
          for rule in tunnel.ingress : rule.zone_id == null ? "" : rule.zone_id
          if lower(trimspace(rule.hostname)) == hostname
        ])) == 1
      ]
    ]))
    error_message = "Rules for the same hostname within a tunnel disagree on zone_id. The hostname has one DNS record, in one zone - give every rule for it the same zone_id, or none."
  }

  validation {
    condition = alltrue(flatten([
      for tunnel in var.tunnels : [
        for rule in tunnel.ingress : rule.zone_id == null ? true : can(regex("^[0-9a-f]{32}$", rule.zone_id))
      ]
    ]))
    error_message = "Each tunnels[*].ingress[*].zone_id, when set, must be a 32-character hexadecimal Cloudflare zone identifier."
  }

  validation {
    condition = alltrue(flatten([
      for tunnel in var.tunnels : [
        for request in concat([tunnel.origin_request], [for rule in tunnel.ingress : rule.origin_request]) :
        length(request.access.aud_tags) > 0 && can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", lower(trimspace(request.access.team_name))))
        if try(request.access, null) != null
      ]
    ]))
    error_message = "Each origin_request.access must name the Zero Trust team_name (the \"acme\" in acme.cloudflareaccess.com) and at least one Access application AUD tag in aud_tags. With no AUD tag cloudflared has nothing to validate the token against."
  }

  validation {
    condition = alltrue(flatten([
      for tunnel in var.tunnels : [
        for request in concat([tunnel.origin_request], [for rule in tunnel.ingress : rule.origin_request]) :
        request.proxy_type == null ? true : contains(["", "socks"], request.proxy_type)
        if request != null
      ]
    ]))
    error_message = "origin_request.proxy_type must be \"\" for the regular proxy or \"socks\" for a SOCKS5 proxy."
  }
}

variable "virtual_networks" {
  type = list(object({
    name               = string
    comment            = optional(string)
    is_default_network = optional(bool, false)
  }))
  default     = []
  description = <<-EOT
    Virtual networks: separate private routing tables, so two sites that both use
    10.0.0.0/16 can each be reached without their routes colliding. Every account
    already has one named "default"; declare more only where address space
    overlaps.

      - name               : identity here and in Cloudflare, matched lower-cased
                             and trimmed. Renaming destroys and recreates it, and
                             every route scoped to it goes too.
      - comment            : (optional) free text.
      - is_default_network : (optional) make this the network a WARP client uses
                             unless told otherwise. At most one. Taking the role
                             from the account's built-in network changes where
                             every unscoped route resolves, for every user.
  EOT

  validation {
    condition     = alltrue([for network in var.virtual_networks : trimspace(network.name) != ""])
    error_message = "Each virtual_networks[*].name must be a non-empty name."
  }

  validation {
    condition = length(distinct([
      for network in var.virtual_networks : lower(trimspace(network.name))
    ])) == length(var.virtual_networks)
    error_message = "virtual_networks contains duplicate names. Names are compared lower-cased and trimmed - each virtual network must be uniquely named."
  }

  validation {
    condition     = length([for network in var.virtual_networks : network if network.is_default_network]) <= 1
    error_message = "More than one virtual_networks entry sets is_default_network. An account has one default virtual network."
  }
}

variable "routes" {
  type = list(object({
    network              = string
    tunnel_name          = string
    virtual_network_name = optional(string)
    virtual_network_id   = optional(string)
    comment              = optional(string)
  }))
  default     = []
  description = <<-EOT
    Private network routes: which address ranges a WARP client reaches through
    which tunnel.

      - network              : the range, in CIDR notation. IPv4 or IPv6.
      - tunnel_name          : a tunnel declared in `tunnels`.
      - virtual_network_name : (optional) a virtual network declared in
                               `virtual_networks`.
      - virtual_network_id   : (optional) the same, for one managed elsewhere.
                               Give at most one of the two; neither means the
                               account's default virtual network.
      - comment              : (optional) free text, up to 100 characters.

    A range is reached through one tunnel per virtual network. Redundancy for a
    site is more connectors on the same tunnel, not a second route.
  EOT

  validation {
    condition     = alltrue([for route in var.routes : can(cidrhost(trimspace(route.network), 0))])
    error_message = "Each routes[*].network must be a CIDR range such as \"10.20.0.0/16\". A single address needs an explicit /32 or /128."
  }

  # An address inside the range rather than the range itself is almost always a
  # typo for a different range, and it reads as one thing in a pull request and
  # another in the dashboard.
  validation {
    condition = alltrue([
      for route in var.routes :
      can(regex(":", route.network)) ? true : try(cidrhost(trimspace(route.network), 0) == split("/", trimspace(route.network))[0], false)
    ])
    error_message = "Each IPv4 routes[*].network must be written as its network address - \"10.20.0.0/16\", not \"10.20.1.5/16\"."
  }

  validation {
    condition     = alltrue([for route in var.routes : trimspace(route.tunnel_name) != ""])
    error_message = "Each routes[*].tunnel_name must name a tunnel."
  }

  validation {
    condition     = alltrue([for route in var.routes : route.virtual_network_name == null || route.virtual_network_id == null])
    error_message = "A routes entry sets both virtual_network_name and virtual_network_id. Give the name for a virtual network this module declares, the ID for one managed elsewhere, or neither for the account's default."
  }

  validation {
    condition = alltrue([
      for route in var.routes :
      route.virtual_network_id == null ? true : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", route.virtual_network_id))
    ])
    error_message = "Each routes[*].virtual_network_id, when set, must be a lower-case UUID."
  }

  validation {
    condition     = alltrue([for route in var.routes : route.comment == null ? true : length(route.comment) <= 100])
    error_message = "Each routes[*].comment must be 100 characters or fewer. Cloudflare rejects anything longer."
  }
}
