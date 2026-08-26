output "namespace_id" {
  value       = cloudflare_workers_kv_namespace.this.id
  description = "Opaque namespace identifier. This is what a Worker's kv_namespace binding points at, and what `wrangler kv bulk put --namespace-id` takes."
}

output "title" {
  value       = cloudflare_workers_kv_namespace.this.title
  description = "Human-readable namespace name as Cloudflare holds it."
}

output "supports_url_encoding" {
  value       = cloudflare_workers_kv_namespace.this.supports_url_encoding
  description = "Whether keys written through the URL are percent-decoded before storage. Namespaces created by this module are new, so this is the current Cloudflare default rather than a setting the operator chose."
}

output "managed_key_count" {
  value       = length(cloudflare_workers_kv.this)
  description = "How many keys Terraform owns in this namespace. Keys written by the application or by `wrangler kv bulk put` are not counted and are not touched by an apply."
}

output "managed_key_names" {
  value       = sort(keys(cloudflare_workers_kv.this))
  description = "The key names Terraform owns. Names only - values are omitted deliberately, so that a layer output cannot become the reason KV contents end up in a pipeline log."
}
