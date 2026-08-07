output "r2_buckets" {
  description = "Per-bucket identifiers and endpoints, keyed by bucket key. `public_r2_dev_domain` is non-null only where anonymous public access is switched on, so an empty value across the board is the expected reading."
  value = {
    for key, bucket in module.r2_buckets : key => {
      name                 = bucket.bucket_name
      location             = bucket.location
      jurisdiction         = bucket.jurisdiction
      s3_endpoint          = bucket.s3_endpoint
      public_r2_dev_domain = bucket.public_r2_dev_domain
      custom_domains       = bucket.custom_domains
    }
  }
}

output "resolved_zone_ids" {
  description = "Zone key => zone ID as resolved by name, for the zones a custom domain references. Empty when no bucket is served from a hostname."
  value       = { for key, zone in data.cloudflare_zone.this : key => zone.id }
}
