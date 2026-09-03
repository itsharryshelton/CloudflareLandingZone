variable "zone_id" {
  type        = string
  description = "Target Cloudflare Zone ID (typically module.zone_base.zone_id)."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hexadecimal Cloudflare zone identifier."
  }
}

variable "ruleset_name" {
  type        = string
  default     = "Origin rules"
  description = "Display name for the origin ruleset (http_request_origin phase)."
}

variable "rules" {
  type = list(object({
    name        = string
    expression  = string
    description = optional(string)
    enabled     = optional(bool, true)

    host_header = optional(string)
    origin = optional(object({
      host = optional(string)
      port = optional(number)
    }))
    sni = optional(object({
      value = string
    }))
  }))
  default     = []
  description = <<-EOT
    Origin rules deployed to the http_request_origin phase, in list order. Each
    is a `route` action: it sends a matching request to somewhere other than the
    origin the DNS record points at, without a redirect the client can see.

      - `name`        : stable label, unique within the ruleset. Used as the
                        description when none is given.
      - `expression`  : Cloudflare Ruleset (wirefilter) expression.
      - `enabled`     : deploy the rule but leave it inactive when false.
      - `host_header` : the Host header sent to the origin. Change this when the
                        origin serves several sites off one address and picks by
                        Host.
      - `origin.host` : the hostname to connect to instead of the one resolved
                        from DNS. It must be a proxied record in a zone on this
                        account, or an address Cloudflare can resolve.
      - `origin.port` : origin port override.
      - `sni.value`   : the SNI presented on the TLS handshake to the origin.
                        Set this when the origin's certificate is issued for a
                        name other than `origin.host`, otherwise the handshake
                        fails.

    PLAN GATING. Origin Rules are not uniformly available: the port and SNI
    overrides in particular are Enterprise features. Cloudflare rejects the whole
    ruleset when the zone is not entitled, which takes the other rules in this
    phase down with the one that was not allowed.

    SECURITY. A route rule silently changes which server answers for a hostname,
    and nothing in the URL or the response tells a visitor it happened. Two
    consequences worth being explicit about:

      - The destination must be an origin you control. Pointing a path at a
        third-party host makes your domain, your TLS certificate and your cookies
        front for someone else's server.
      - Changing `host_header` changes what the origin thinks it is serving,
        which can move it onto a different vhost, a different auth realm or a
        different set of cookies. Check the origin's routing before assuming a
        host header override is cosmetic.
  EOT

  validation {
    condition = alltrue([
      for r in var.rules : trimspace(r.name) != "" && trimspace(r.expression) != ""
    ])
    error_message = "Each rules entry must set a non-empty `name` and `expression`."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.host_header != null || r.origin != null || r.sni != null
    ])
    error_message = "Each rules entry must set at least one of host_header, origin or sni; a route rule that routes nowhere matches traffic and does nothing."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.origin == null || try(r.origin.host, null) != null || try(r.origin.port, null) != null
    ])
    error_message = "rules[*].origin must set `host`, `port` or both. An empty origin object is rejected by Cloudflare."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      try(r.origin.port, null) == null || (try(r.origin.port, 0) >= 1 && try(r.origin.port, 0) <= 65535)
    ])
    error_message = "rules[*].origin.port must be between 1 and 65535."
  }
}
