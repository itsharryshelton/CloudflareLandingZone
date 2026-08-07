# Cross-variable checks. A module block cannot carry lifecycle.precondition and
# variable validation cannot compare two variables, so they live on a state-only
# resource from Terraform's built-in provider. No credentials, no API calls.

resource "terraform_data" "preflight" {
  input = {
    r2_buckets       = length(var.r2_buckets)
    referenced_zones = length(local.referenced_zones)
  }

  lifecycle {
    precondition {
      condition     = length(local.dangling_zone_keys) == 0
      error_message = "zone_key does not match any entry in var.zones: ${join("; ", local.dangling_zone_keys)}. Valid keys: ${join(", ", keys(var.zones))}. Both layers must be given the same accounts/<account>/zones.tfvars."
    }

    precondition {
      condition     = length(local.hostnames_outside_zone) == 0
      error_message = "A custom domain hostname is not inside the zone it references: ${join("; ", local.hostnames_outside_zone)}. Cloudflare would reject it only after creating the bucket, leaving the layer half-applied."
    }

    precondition {
      condition     = length(local.public_r2_dev_buckets) == 0
      error_message = "These buckets ask for anonymous public access on their r2.dev URL: ${join("; ", local.public_r2_dev_buckets)}. That serves every object in the bucket to anyone who knows a key, with no authentication and no cache, and Cloudflare intends it for development. Serve objects publicly through a custom_domains entry instead, or set allow_public_r2_dev_domains = true in layers/r2/defaults.auto.tfvars on a pull request that says why."
    }

    precondition {
      condition     = length(local.wildcard_cors_rules) == 0
      error_message = "These CORS rules allow every origin on the internet: ${join("; ", local.wildcard_cors_rules)}. A wildcard lets any page a visitor opens read the bucket from their browser, using their network position. List the origins that need access, or set allow_wildcard_cors_origins = true in layers/r2/defaults.auto.tfvars."
    }

    precondition {
      condition     = length(local.bucket_wide_expiry_rules) == 0
      error_message = "These lifecycle rules delete objects with an empty prefix, which means the entire bucket on a schedule: ${join("; ", local.bucket_wide_expiry_rules)}. R2 has no versioning, so nothing deleted comes back. Scope the rule with a prefix, or set allow_bucket_wide_object_expiry = true in layers/r2/defaults.auto.tfvars if the bucket really is scratch space."
    }
  }
}
