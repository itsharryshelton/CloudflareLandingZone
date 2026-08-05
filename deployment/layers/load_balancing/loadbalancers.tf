# Traffic management: one health monitor, origin pool and load balancer per entry.
#
# Downstream deployments pin an immutable tag instead of the local path - review root readme.md for more info:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/load_balancer?ref=v1.0.0"
module "load_balancers" {
  source = "../../../modules/load_balancer"

  for_each = local.load_balancers

  # Monitors and pools are account-scoped; the load balancer itself is zone-scoped. (LB Account Level is Enterprise Plan; Self-Service is Zone Level - specifically put as Zone Level)
  account_id = var.cloudflare_account_id

  # zone_key -> zone ID, resolved by name in zone_lookup.tf.
  zone_id = data.cloudflare_zone.this[each.value.zone_key].id

  lb_hostname = each.value.lb_hostname
  origins     = each.value.origins

  proxied                 = each.value.proxied
  steering_policy         = each.value.steering_policy
  session_affinity        = each.value.session_affinity
  pool_minimum_origins    = each.value.pool_minimum_origins
  pool_notification_email = each.value.pool_notification_email

  # Grouped into one object for the operator
  health_check_type           = each.value.health_check.type
  health_check_path           = each.value.health_check.path
  health_check_port           = each.value.health_check.port
  health_check_method         = each.value.health_check.method
  health_check_expected_codes = each.value.health_check.expected_codes
  health_check_interval       = each.value.health_check.interval
  health_check_timeout        = each.value.health_check.timeout
  health_check_retries        = each.value.health_check.retries
}
