output "dns_record_ids" {
  description = <<-EOT
    Zone key => (record key => Cloudflare record ID).

    Same shape as the zones layer's output of the same name, so an operator
    comparing the two during a cutover is comparing like with like.
  EOT
  value       = { for key, dns in module.dns : key => dns.record_ids }
}

output "record_counts" {
  description = "Zone key => number of Terraform-managed records. The quickest check that a var file reached this layer."
  value       = { for key, dns in module.dns : key => dns.record_count }
}

output "zone_ids" {
  description = "Zone key => resolved zone ID, for the zones this layer manages records in. Each one cost an API read at plan time."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.zone_id }
}
