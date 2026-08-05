output "load_balancer_id" {
  value       = cloudflare_load_balancer.this.id
  description = "ID of the load balancer."
}

output "load_balancer_hostname" {
  value       = cloudflare_load_balancer.this.name
  description = "Hostname the load balancer answers on."
}

output "pool_id" {
  value       = cloudflare_load_balancer_pool.this.id
  description = "ID of the origin pool."
}

output "monitor_id" {
  value       = cloudflare_load_balancer_monitor.this.id
  description = "ID of the health check monitor."
}
