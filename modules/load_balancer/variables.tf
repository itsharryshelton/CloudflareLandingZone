variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. Pools and monitors are account-scoped resources."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "zone_id" {
  type        = string
  description = "Target Cloudflare Zone ID for the load balancer (typically module.zone_base.zone_id)."
}

variable "lb_hostname" {
  type        = string
  description = "Fully-qualified hostname the load balancer answers on (e.g. app.example.com)."

  validation {
    condition     = can(regex("^([a-z0-9_]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.lb_hostname))
    error_message = "lb_hostname must be a fully-qualified, lowercase hostname (e.g. app.example.com) with no scheme, port or path."
  }
}

variable "origins" {
  type = list(object({
    name        = string
    address     = string
    enabled     = optional(bool, true)
    weight      = optional(number, 1)
    port        = optional(number)
    header_host = optional(list(string))
  }))
  description = <<-EOT
    Origin servers behind the load balancer (a single pool is created).
      - name       : label for the origin; must be unique within the pool.
      - address    : IP or hostname of the origin.
      - weight     : 0.0-1.0 relative weight for weighted steering policies.
      - port       : optional origin port override.
      - header_host: optional Host header override sent to the origin. Cloudflare
                     models this as a list, so pass one or more values, e.g.
                     header_host = ["origin.internal.example.com"].
    In provider v5 `origins` is a list attribute (origins = [ {...} ]), not a
    set of dynamic "origins" blocks as in v4.
  EOT

  validation {
    condition     = length(var.origins) > 0
    error_message = "At least one origin is required."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.weight >= 0 && o.weight <= 1])
    error_message = "Each origin weight must be between 0.0 and 1.0."
  }

  validation {
    condition     = alltrue([for o in var.origins : trimspace(o.name) != "" && trimspace(o.address) != ""])
    error_message = "Each origin must set a non-empty `name` and `address`."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.port == null || (o.port >= 1 && o.port <= 65535)])
    error_message = "Each origin `port`, when set, must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.header_host == null || length(coalesce(o.header_host, [])) > 0])
    error_message = "Each origin `header_host`, when set, must contain at least one hostname."
  }
}

variable "proxied" {
  type        = bool
  default     = true
  description = "Whether the load balancer hostname is proxied (orange-cloud) through Cloudflare."
}

variable "steering_policy" {
  type        = string
  default     = null
  description = <<-EOT
    Traffic steering policy. Null lets Cloudflare use its default (failover by
    pool order). One of: off, geo, random, dynamic_latency, proximity,
    least_outstanding_requests, least_connections.
  EOT

  validation {
    condition = var.steering_policy == null || contains(
      ["off", "geo", "random", "dynamic_latency", "proximity",
      "least_outstanding_requests", "least_connections"],
      var.steering_policy
    )
    error_message = "steering_policy must be null or one of: off, geo, random, dynamic_latency, proximity, least_outstanding_requests, least_connections."
  }
}

variable "session_affinity" {
  type        = string
  default     = "none"
  description = "Session affinity mode. One of: none, cookie, ip_cookie, header."

  validation {
    condition     = contains(["none", "cookie", "ip_cookie", "header"], var.session_affinity)
    error_message = "session_affinity must be one of: none, cookie, ip_cookie, header."
  }
}

variable "pool_minimum_origins" {
  type        = number
  default     = 1
  description = "Minimum number of healthy origins required to keep the pool healthy. Cannot exceed the number of origins supplied."

  validation {
    condition     = var.pool_minimum_origins >= 1
    error_message = "pool_minimum_origins must be at least 1."
  }
}

variable "pool_notification_email" {
  type        = string
  default     = null
  description = "Optional email address to notify on pool health changes."

  validation {
    condition     = var.pool_notification_email == null || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[a-zA-Z]{2,}$", coalesce(var.pool_notification_email, "")))
    error_message = "pool_notification_email must be a single valid email address, or null."
  }
}

# ---------------------------------------------------------------------------
# Health check monitor
# ---------------------------------------------------------------------------
variable "health_check_type" {
  type        = string
  default     = "https"
  description = "Monitor protocol. One of: http, https, tcp, udp_icmp, icmp_ping, smtp."

  validation {
    condition     = contains(["http", "https", "tcp", "udp_icmp", "icmp_ping", "smtp"], var.health_check_type)
    error_message = "health_check_type must be one of: http, https, tcp, udp_icmp, icmp_ping, smtp."
  }
}

variable "health_check_path" {
  type        = string
  default     = "/healthz"
  description = "Request path for http/https health checks."

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must begin with \"/\"."
  }
}

variable "health_check_port" {
  type        = number
  default     = 443
  description = "Port the monitor probes."

  validation {
    condition     = var.health_check_port >= 1 && var.health_check_port <= 65535
    error_message = "health_check_port must be between 1 and 65535."
  }
}

variable "health_check_method" {
  type        = string
  default     = "GET"
  description = "HTTP method for http/https health checks. One of: GET, HEAD."

  validation {
    condition     = contains(["GET", "HEAD"], upper(var.health_check_method))
    error_message = "health_check_method must be GET or HEAD."
  }
}

variable "health_check_expected_codes" {
  type        = string
  default     = "2xx"
  description = "Expected HTTP status code(s) for a healthy origin (e.g. '2xx' or '200')."

  validation {
    condition     = can(regex("^([1-5]xx|[1-5][0-9]{2})$", var.health_check_expected_codes))
    error_message = "health_check_expected_codes must be a status class (e.g. \"2xx\") or a single status code (e.g. \"200\")."
  }
}

variable "health_check_interval" {
  type        = number
  default     = 60
  description = "Seconds between health checks. Must be longer than health_check_timeout."

  validation {
    condition     = var.health_check_interval >= 10 && var.health_check_interval <= 3600
    error_message = "health_check_interval must be between 10 and 3600 seconds."
  }
}

variable "health_check_timeout" {
  type        = number
  default     = 5
  description = "Seconds to wait for a health check response before timing out."

  validation {
    condition     = var.health_check_timeout >= 1 && var.health_check_timeout <= 60
    error_message = "health_check_timeout must be between 1 and 60 seconds."
  }
}

variable "health_check_retries" {
  type        = number
  default     = 2
  description = "Retries before marking an origin unhealthy."

  validation {
    condition     = var.health_check_retries >= 0 && var.health_check_retries <= 5
    error_message = "health_check_retries must be between 0 and 5."
  }
}
