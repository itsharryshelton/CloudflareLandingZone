# Origin mapping and normalisation lives in locals.tf.

resource "cloudflare_load_balancer_monitor" "this" {
  account_id     = var.account_id
  type           = var.health_check_type
  method         = var.health_check_method
  path           = var.health_check_path
  port           = var.health_check_port
  expected_codes = var.health_check_expected_codes
  interval       = var.health_check_interval
  timeout        = var.health_check_timeout
  retries        = var.health_check_retries
  description    = "Health check for ${var.lb_hostname}"

  lifecycle {
    precondition {
      condition     = var.health_check_timeout < var.health_check_interval
      error_message = "health_check_timeout (${var.health_check_timeout}s) must be shorter than health_check_interval (${var.health_check_interval}s), otherwise probes overlap."
    }
  }
}

resource "cloudflare_load_balancer_pool" "this" {
  account_id         = var.account_id
  name               = "${var.lb_hostname}-pool"
  monitor            = cloudflare_load_balancer_monitor.this.id
  minimum_origins    = var.pool_minimum_origins
  notification_email = var.pool_notification_email
  description        = "Origin pool for ${var.lb_hostname}"

  origins = local.origins

  lifecycle {
    precondition {
      condition     = length(distinct(local.origin_names)) == length(local.origin_names)
      error_message = "origins[*].name must be unique within the pool."
    }

    precondition {
      condition     = var.pool_minimum_origins <= length(var.origins)
      error_message = "pool_minimum_origins (${var.pool_minimum_origins}) cannot exceed the number of origins (${length(var.origins)}), or the pool can never become healthy."
    }
  }
}

resource "cloudflare_load_balancer" "this" {
  zone_id          = var.zone_id
  name             = var.lb_hostname
  default_pools    = [cloudflare_load_balancer_pool.this.id]
  fallback_pool    = cloudflare_load_balancer_pool.this.id
  proxied          = var.proxied
  steering_policy  = var.steering_policy
  session_affinity = var.session_affinity
  description      = "Managed by Terraform (cloudflarelandingzone/modules/load_balancer)."

  # These attributes are populated with computed defaults by the Cloudflare API
  # and otherwise show perpetual drift. See the provider's known-drift notes.
  #
  # NOTE: leaving steering_policy null makes the provider send "", which
  # Cloudflare interprets as its default (failover in pool order). That is the
  # intended behaviour - set the variable explicitly to pin a policy.
  lifecycle {
    ignore_changes = [adaptive_routing, random_steering]
  }
}
