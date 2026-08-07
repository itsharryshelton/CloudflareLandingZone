# One R2 bucket and everything Cloudflare models as a separate object hanging off
# it: CORS, object lifecycle, object lock, the r2.dev public URL and any custom
# domains. Normalisation lives in locals.tf.
#
# The bucket resource creates the bucket and nothing else. Each configuration
# resource below owns its whole list, so removing an entry from a variable
# removes the rule from Cloudflare rather than leaving it behind.

resource "cloudflare_r2_bucket" "this" {
  account_id    = var.account_id
  name          = var.name
  location      = var.location
  storage_class = var.storage_class
  jurisdiction  = local.jurisdiction

  lifecycle {
    precondition {
      condition     = length(distinct(local.lifecycle_rule_ids)) == length(local.lifecycle_rule_ids)
      error_message = "lifecycle_rules[*].id must be unique within a bucket: ${join(", ", local.lifecycle_rule_ids)}. R2 keys rules on the id, so a duplicate silently replaces the earlier rule instead of adding to it."
    }

    precondition {
      condition     = length(distinct(local.lock_rule_ids)) == length(local.lock_rule_ids)
      error_message = "lock_rules[*].id must be unique within a bucket: ${join(", ", local.lock_rule_ids)}."
    }

    precondition {
      condition     = length(local.lifecycle_deletions_over_locked_objects) == 0
      error_message = "A lifecycle rule would delete objects that an object lock rule retains: ${join("; ", local.lifecycle_deletions_over_locked_objects)}. R2 accepts both and then refuses the deletion object by object until retention expires, so the storage is paid for and nothing reports why. Narrow one of the two prefixes."
    }

    precondition {
      condition     = length(local.redundant_storage_class_transitions) == 0
      error_message = "storage_class is already InfrequentAccess, so these rules transition objects to the class they were written in and do nothing: ${join(", ", local.redundant_storage_class_transitions)}. Either write new objects as Standard, or drop the transition."
    }
  }
}

resource "cloudflare_r2_bucket_cors" "this" {
  count = length(local.cors_rules) > 0 ? 1 : 0

  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.this.name
  jurisdiction = local.jurisdiction

  rules = local.cors_rules

  lifecycle {
    precondition {
      condition     = length(distinct(local.cors_rule_ids)) == length(local.cors_rule_ids)
      error_message = "cors_rules[*].id must be unique where it is set: ${join(", ", local.cors_rule_ids)}."
    }
  }
}

resource "cloudflare_r2_bucket_lifecycle" "this" {
  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.this.name
  jurisdiction = local.jurisdiction

  rules = local.lifecycle_rules
}

resource "cloudflare_r2_bucket_lock" "this" {
  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.this.name
  jurisdiction = local.jurisdiction

  rules = local.lock_rules
}

# Declared whether or not public access is wanted. Managing only the "on" case
# would mean the dashboard toggle that makes a bucket anonymously readable is
# invisible to Terraform, and a plan that says "no changes" would be wrong.
resource "cloudflare_r2_managed_domain" "this" {
  count = var.manage_r2_dev_domain ? 1 : 0

  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.this.name
  jurisdiction = local.jurisdiction
  enabled      = var.public_r2_dev_domain
}

resource "cloudflare_r2_custom_domain" "this" {
  for_each = local.custom_domains

  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.this.name
  jurisdiction = local.jurisdiction

  domain  = each.key
  zone_id = each.value.zone_id
  enabled = each.value.enabled
  min_tls = each.value.min_tls
  ciphers = each.value.ciphers

  lifecycle {
    precondition {
      condition     = length(distinct(local.custom_domain_names)) == length(local.custom_domain_names)
      error_message = "custom_domains[*].domain must be unique within a bucket: ${join(", ", local.custom_domain_names)}. Hostnames are compared lower-cased."
    }
  }
}
