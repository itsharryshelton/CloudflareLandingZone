# Object storage: one R2 bucket per entry, with its CORS, lifecycle, retention
# and public hostname configuration.
#
# Downstream deployments pin an immutable tag instead of the local path - review root readme.md for more info:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/r2_bucket?ref=v1.0.0"
module "r2_buckets" {
  source = "../../../modules/r2_bucket"

  for_each = local.r2_buckets

  # R2 buckets are account-scoped. No zone is involved unless a custom domain is.
  account_id = var.cloudflare_account_id

  name          = each.value.name
  location      = each.value.location
  storage_class = each.value.storage_class
  jurisdiction  = each.value.jurisdiction

  cors_rules      = each.value.cors_rules
  lifecycle_rules = each.value.lifecycle_rules
  lock_rules      = each.value.lock_rules

  # Declared for every bucket, not only the public ones, so that the dashboard toggle which makes a bucket anonymously readable shows up as drift.
  public_r2_dev_domain = each.value.public_r2_dev_domain

  # zone_key -> zone ID, resolved by name in zone_lookup.tf.
  custom_domains = each.value.custom_domains
}
