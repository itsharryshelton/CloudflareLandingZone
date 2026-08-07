# Applies the platform baseline, resolves zone keys to zone IDs, and derives the
# preflight assertions, so that r2.tf reads as a plain module call.

locals {
  # Only zones a custom domain actually targets are looked up, so a deployment
  # with no public hostnames costs no API call - and can be planned offline.
  referenced_zone_keys = distinct(flatten([
    for bucket in var.r2_buckets : [for domain in bucket.custom_domains : domain.zone_key]
  ]))

  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains(local.referenced_zone_keys, key)
  }

  # Per-bucket settings win; anything unset falls back to the platform baseline.
  #
  # coalesce is deliberately not used for the three that default to null: it
  # raises an error when every argument is null, which is the ordinary "let
  # Cloudflare decide" case here rather than a mistake.
  r2_buckets = {
    for key, bucket in var.r2_buckets : key => merge(bucket, {
      location      = bucket.location != null ? bucket.location : var.default_bucket_location
      storage_class = bucket.storage_class != null ? bucket.storage_class : var.default_storage_class
      jurisdiction  = bucket.jurisdiction != null ? bucket.jurisdiction : var.default_jurisdiction

      # null means "inherit the baseline", [] means "deliberately none". Those
      # are different answers, which is why the variable carries no default.
      lifecycle_rules = bucket.lifecycle_rules != null ? bucket.lifecycle_rules : var.default_lifecycle_rules

      # `if contains(...)` rather than a bare index: a zone_key pointing at
      # nothing must reach the operator as the preflight message naming it, not
      # as "Invalid index" pointing at this file.
      custom_domains = [
        for domain in bucket.custom_domains : {
          domain  = lower(domain.hostname)
          zone_id = data.cloudflare_zone.this[domain.zone_key].id
          enabled = domain.enabled
          min_tls = domain.min_tls != null ? domain.min_tls : var.default_custom_domain_min_tls
          ciphers = domain.ciphers
        }
        if contains(keys(local.referenced_zones), domain.zone_key)
      ]
    })
  }

  # Preflight checks here
  dangling_zone_keys = distinct(flatten([
    for key, bucket in var.r2_buckets : [
      for domain in bucket.custom_domains : "r2_buckets.${key}.custom_domains -> zone_key = \"${domain.zone_key}\""
      if !contains(keys(var.zones), domain.zone_key)
    ]
  ]))

  # Cloudflare rejects a custom domain outside its zone, but only after the
  # bucket exists, leaving a half-applied layer behind.
  hostnames_outside_zone = flatten([
    for key, bucket in var.r2_buckets : [
      for domain in bucket.custom_domains :
      "r2_buckets.${key}: \"${domain.hostname}\" is not within \"${var.zones[domain.zone_key].domain_name}\""
      if contains(keys(var.zones), domain.zone_key)
      && !endswith(lower(domain.hostname), lower(var.zones[domain.zone_key].domain_name))
    ]
  ])

  # Governing defaults. Each of these is a configuration that Cloudflare accepts
  # happily and that quietly widens who can read the data.
  public_r2_dev_buckets = var.allow_public_r2_dev_domains ? [] : [
    for key, bucket in var.r2_buckets : "r2_buckets.${key} (\"${bucket.name}\")"
    if bucket.public_r2_dev_domain
  ]

  wildcard_cors_rules = var.allow_wildcard_cors_origins ? [] : distinct(flatten([
    for key, bucket in var.r2_buckets : [
      for index, rule in bucket.cors_rules :
      "r2_buckets.${key}.cors_rules[${index}]${rule.id == null ? "" : " (\"${rule.id}\")"}"
      if contains(rule.allowed_origins, "*")
    ]
  ]))

  # Only deletions. Aborting an incomplete multipart upload bucket-wide is the
  # shipped baseline and destroys nothing an application successfully wrote.
  bucket_wide_expiry_rules = var.allow_bucket_wide_object_expiry ? [] : distinct(flatten([
    for key, bucket in local.r2_buckets : [
      for rule in bucket.lifecycle_rules : "r2_buckets.${key}.lifecycle_rules.${rule.id}"
      if rule.enabled
      && trimspace(rule.prefix) == ""
      && (rule.delete_objects_after_days != null || rule.delete_objects_on_date != null)
    ]
  ]))
}
