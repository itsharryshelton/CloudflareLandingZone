output "load_balancers" {
  description = "Per-load-balancer identifiers, keyed by load balancer key."
  value = {
    for key, lb in module.load_balancers : key => {
      load_balancer_id = lb.load_balancer_id
      hostname         = lb.load_balancer_hostname
      pool_id          = lb.pool_id
      monitor_id       = lb.monitor_id
    }
  }
}

output "resolved_zone_ids" {
  description = "Zone key => zone ID as resolved by name. Useful for confirming this layer bound to the zones you expected."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.id }
}
