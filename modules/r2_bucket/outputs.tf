output "bucket_name" {
  value       = cloudflare_r2_bucket.this.name
  description = "Name of the bucket, as an application's S3 client needs it."
}

output "bucket_id" {
  value       = cloudflare_r2_bucket.this.id
  description = "Cloudflare's identifier for the bucket. R2 uses the bucket name as its ID, so this matches bucket_name."
}

output "location" {
  value       = cloudflare_r2_bucket.this.location
  description = "Location the bucket was actually placed in, which is Cloudflare's choice when var.location is null and is fixed once the bucket exists."
}

output "jurisdiction" {
  value       = cloudflare_r2_bucket.this.jurisdiction
  description = "Data residency jurisdiction the bucket was created in. Every API call against the bucket has to name the same one."
}

output "creation_date" {
  value       = cloudflare_r2_bucket.this.creation_date
  description = "When the bucket was created."
}

output "s3_endpoint" {
  value       = "https://${var.account_id}.r2.cloudflarestorage.com/${cloudflare_r2_bucket.this.name}"
  description = <<-EOT
    S3-compatible endpoint for the bucket. Reaching it needs an R2 access key,
    which this module deliberately does not create - a credential does not belong
    in Terraform state.

    Buckets in a non-default jurisdiction are served from a jurisdiction-specific
    host instead (for example <account>.eu.r2.cloudflarestorage.com), so check
    `jurisdiction` before wiring this into a client.
  EOT
}

output "public_r2_dev_domain" {
  value       = var.manage_r2_dev_domain && var.public_r2_dev_domain ? try(cloudflare_r2_managed_domain.this[0].domain, null) : null
  description = "The bucket's pub-<hash>.r2.dev hostname when anonymous public access is switched on, and null when it is not. A non-null value here means every object in the bucket is readable by anyone."
}

output "custom_domains" {
  value = {
    for domain, resource in cloudflare_r2_custom_domain.this : domain => {
      enabled          = resource.enabled
      zone_id          = resource.zone_id
      min_tls          = resource.min_tls
      ownership_status = try(resource.status.ownership, null)
      ssl_status       = try(resource.status.ssl, null)
    }
  }
  description = "Per-hostname state of the bucket's custom domains. `ownership_status` and `ssl_status` sit at \"pending\" or \"initializing\" for a few minutes after a domain is first attached; the hostname does not serve until both reach \"active\"."
}
