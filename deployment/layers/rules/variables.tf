# Layer rules - inputs.
#
# The three zone ruleset phases that shape traffic rather than block it: cache
# settings, request header transforms, and origin selection. Holds its own state,
# so an apply here can never propose destroying a zone.
#
# Deliberately NOT here:
#   http_request_firewall_custom, http_ratelimit  - layers/waf
#   http_request_redirect                         - layers/bulk_redirects
#
# Config files:
#   accounts/<account>/account.tfvars - the account ID, shared with every layer
#   accounts/<account>/zones.tfvars   - the zone inventory, shared with every layer
#   accounts/<account>/rules.tfvars   - the policies, consumed only here

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Used to scope the zone lookup, so a zone name that also exists in another account cannot be picked up by accident."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zones" {
  description = <<-EOT
    Zone inventory: logical key => domain name. The same file the zones layer is
    given, so the keys mean the same thing in both.
  EOT

  type = map(object({
    domain_name = string
    zone_tier   = optional(string)
  }))
  default = {}
}

variable "rule_policies" {
  description = <<-EOT
    A map of traffic rule policies, one per zone that needs cache, transform or
    origin rules, keyed by a logical key. A zone with no policy gets no rulesets
    at all, which costs nothing.

    - `zone_key`        - The key of the zone this policy binds to. Taken from `var.zones`.
    - `cache_rules`     - (Optional) http_request_cache_settings. What Cloudflare stores
                          and how it keys it.
    - `transform_rules` - (Optional) http_request_late_transform. Request headers sent to
                          the origin. Late, so a WAF rule cannot match on what they set.
    - `origin_rules`    - (Optional) http_request_origin. Where a matching request is
                          actually sent.
    - `*_ruleset_name`  - (Optional) Dashboard display names, one per phase.

    ORDERING DIFFERS BY PHASE, which is the thing most likely to catch someone
    out. In the cache phase Cloudflare applies every matching rule and the LAST
    one wins, so exceptions go after the broad rules. In the origin phase the
    FIRST match wins. Getting this backwards produces a config that reads
    correctly and behaves inversely.

    SECURITY. Cache rules decide what Cloudflare stores and serves to the next
    visitor, so caching a response that varies per user leaks one user's data to
    another. `cache = true` overrides Cloudflare's own eligibility checks,
    including the ones that keep a response with a session cookie private, so a
    rule setting it must either mention a cookie or an Authorization header in
    its expression or set `acknowledge_public_response = true` to state that the
    matched responses genuinely are the same for everyone. The plan fails
    otherwise.

    Transform rules must not carry credentials: a value here is stored in plain
    text in Terraform state and printed in every plan, so it ends up in state
    storage, CI logs and pull request output. Origin rules silently change which
    server answers for a hostname, with nothing in the URL or the response to say
    so, which means the destination has to be an origin you control.
  EOT

  type = map(object({
    zone_key = string

    cache_ruleset_name     = optional(string)
    transform_ruleset_name = optional(string)
    origin_ruleset_name    = optional(string)

    cache_rules = optional(list(object({
      name        = string
      expression  = string
      description = optional(string)
      enabled     = optional(bool, true)

      cache                       = optional(bool)
      acknowledge_public_response = optional(bool, false)

      cache_key = optional(object({
        cache_by_device_type       = optional(bool)
        cache_deception_armor      = optional(bool)
        ignore_query_strings_order = optional(bool)

        custom_key = optional(object({
          query_string = optional(object({
            include = optional(object({
              all  = optional(bool)
              list = optional(list(string))
            }))
            exclude = optional(object({
              all  = optional(bool)
              list = optional(list(string))
            }))
          }))
          host = optional(object({
            resolved = optional(bool)
          }))
          header = optional(object({
            include        = optional(list(string))
            check_presence = optional(list(string))
            contains       = optional(map(list(string)))
            exclude_origin = optional(bool)
          }))
          cookie = optional(object({
            include        = optional(list(string))
            check_presence = optional(list(string))
          }))
          user = optional(object({
            device_type = optional(bool)
            geo         = optional(bool)
            lang        = optional(bool)
          }))
        }))
      }))

      edge_ttl = optional(object({
        mode    = string
        default = optional(number)
        status_code_ttl = optional(list(object({
          value       = number
          status_code = optional(number)
          status_code_range = optional(object({
            from = optional(number)
            to   = optional(number)
          }))
        })))
      }))

      browser_ttl = optional(object({
        mode    = string
        default = optional(number)
      }))

      serve_stale = optional(object({
        disable_stale_while_updating = optional(bool)
      }))

      respect_strong_etags       = optional(bool)
      origin_cache_control       = optional(bool)
      origin_error_page_passthru = optional(bool)
      read_timeout               = optional(number)
    })), [])

    transform_rules = optional(list(object({
      name        = string
      expression  = string
      description = optional(string)
      enabled     = optional(bool, true)
      headers = map(object({
        operation  = string
        value      = optional(string)
        expression = optional(string)
      }))
    })), [])

    origin_rules = optional(list(object({
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
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.rule_policies) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "rule_policies keys must be lowercase alphanumeric with underscores."
  }

  validation {
    condition     = length(distinct([for p in var.rule_policies : p.zone_key])) == length(var.rule_policies)
    error_message = "Two rule_policies entries target the same zone_key. Cloudflare allows one entry-point ruleset per phase per zone, so the second would fight the first - merge them into one policy."
  }
}
