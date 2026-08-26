output "script_name" {
  value       = cloudflare_workers_script.this.script_name
  description = "Name of the Worker. This is what a route, a service binding or `wrangler tail` refers to it by."
}

output "id" {
  value       = cloudflare_workers_script.this.id
  description = "Cloudflare's identifier for the Worker, which is its name."
}

output "etag" {
  value       = cloudflare_workers_script.this.etag
  description = "Hash of the deployed script contents. Two Workers with the same etag are running identical code, which is the quickest way to tell whether a deploy actually landed."
}

output "has_modules" {
  value       = cloudflare_workers_script.this.has_modules
  description = "Whether Cloudflare parsed the upload as ES module syntax. False on a Worker meant to be modular means main_module was set but the source still uses addEventListener, and bindings will be undefined on `env`."
}

output "created_on" {
  value       = cloudflare_workers_script.this.created_on
  description = "When the Worker was first created."
}

output "modified_on" {
  value       = cloudflare_workers_script.this.modified_on
  description = "When the Worker was last modified, by anything - including a dashboard edit that this configuration will overwrite on the next apply."
}

output "routes" {
  value       = { for pattern, route in cloudflare_workers_route.this : pattern => route.id }
  description = "Route pattern => route ID for every pattern sending traffic to this Worker."
}

output "custom_domains" {
  value = {
    for hostname, domain in cloudflare_workers_custom_domain.this : hostname => {
      id      = domain.id
      zone_id = domain.zone_id
      cert_id = domain.cert_id
    }
  }
  description = "Per-hostname state of the Worker's custom domains. `cert_id` is empty until Cloudflare has issued the certificate, which takes a few minutes after a hostname is first attached."
}

output "cron_schedules" {
  value       = var.cron_schedules
  description = "Cron expressions invoking this Worker's scheduled handler. Empty means the Worker only ever runs in response to a request."
}

output "inline_secret_binding_names" {
  value       = local.inline_secret_bindings
  description = "Names of any secret_text bindings on this Worker. Each one means a literal secret value is held in Terraform state and in the variable file it came from; a non-empty list here is worth acting on, and a secrets_store_secret binding is the replacement."
}
