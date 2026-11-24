output "id" {
  description = "UUID of the list. This is what a Gateway policy names, as `$<id>`, and what the gateway module's *_list_ids inputs take."
  value       = cloudflare_zero_trust_list.this.id
}

output "name" {
  description = "Display name of the list."
  value       = cloudflare_zero_trust_list.this.name
}

output "type" {
  description = "List type (DOMAIN, IP, URL, EMAIL, ...). A caller wiring the list into a policy should check it suits the selector, because the gateway module only sees the ID."
  value       = cloudflare_zero_trust_list.this.type
}

output "reference" {
  description = "The list as a Gateway expression refers to it - `$<uuid>` - for pasting into a hand-written traffic_expression or the dashboard's expression editor."
  value       = format("$%s", cloudflare_zero_trust_list.this.id)
}

output "item_count" {
  description = "How many entries Cloudflare reports the list holding, read back after apply. A number lower than the configured entries means Cloudflare merged or dropped some."
  value       = cloudflare_zero_trust_list.this.list_count
}
