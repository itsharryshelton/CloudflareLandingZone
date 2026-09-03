output "record_ids" {
  description = <<-EOT
    Internal record key (TYPE/fqdn/content) => Cloudflare record ID.

    The key is the same one the resource is keyed on in state, so this is what a
    caller needs to build an `import` block for a record that already exists -
    which is how records are adopted out of the zone_base module rather than
    destroyed and recreated.
  EOT
  value       = { for key, record in cloudflare_dns_record.this : key => record.id }
}

output "record_count" {
  description = "Number of records managed in this zone. Cheap check that a var file reached the module."
  value       = length(cloudflare_dns_record.this)
}

output "record_names" {
  description = "Fully-qualified names of every managed record, sorted."
  value       = sort([for record in local.records : record.name])
}
