# Cloudflare resource tags for the R2 buckets this layer owns.
#
# The provider has no tagging resource yet, so nothing here calls the Tagging
# API. This resolves each bucket's complete tag set from var.resource_tags and
# outputs it with the bucket ID; .github/scripts/resource-tags.sh applies it
# after the apply, from a job holding a token of its own. The precedence rules
# are in accounts/<account>/tags.tfvars.
#
# When the provider ships a tagging resource, for_each it over
# local.r2_bucket_resource_tags here and retire the script.

locals {
  # Merged last, so an account tree cannot make a resource read as unmanaged or
  # as another layer's.
  pipeline_tags = {
    "managed-by" = "terraform"
    layer        = basename(abspath(path.module))
  }

  # Every bucket, not only those tags.tfvars lists: the pipeline keys are what a
  # `tag=!managed-by` filter relies on to find a bucket somebody created by hand.
  r2_bucket_resource_tags = {
    for key in keys(var.r2_buckets) : key => {
      for k, v in merge(
        var.resource_tags.defaults,
        var.resource_tags.r2_buckets.defaults,
        lookup(var.resource_tags.r2_buckets.resources, key, {}),
        local.pipeline_tags,
      ) : k => v if v != null
    }
  }

  # Preflight checks here. The shared settings and this layer's own section
  # only - another layer's section is that layer's to report.
  resource_tag_sources = merge(
    { "resource_tags.defaults" = var.resource_tags.defaults },
    { "resource_tags.r2_buckets.defaults" = var.resource_tags.r2_buckets.defaults },
    { for key, tags in var.resource_tags.r2_buckets.resources : "resource_tags.r2_buckets.resources.${key}" => tags },
  )

  resource_tag_problems = sort(concat(
    [
      for key in keys(var.resource_tags.r2_buckets.resources) : "resource_tags.r2_buckets.resources.${key} names no bucket in var.r2_buckets"
      if !contains(keys(var.r2_buckets), key)
    ],
    flatten([
      for path, tags in local.resource_tag_sources : concat(
        # ASCII only. Stricter than the API, which also takes letters from other
        # scripts, but a key somebody has to type into a filter should not need them.
        [for k in keys(tags) : "${path}: \"${k}\" is not a valid tag key (letters, digits, _ . - only, at most 256)" if !can(regex("^[a-zA-Z0-9_.-]{1,256}$", k))],
        [for k in keys(tags) : "${path}: \"${k}\" is set by the pipeline and cannot be set here" if contains(keys(local.pipeline_tags), k)],
        [for k, v in { for k, v in tags : k => v if v != null } : "${path}.${k} is longer than 1024 characters" if length(v) > 1024],
        [
          for k, v in { for k, v in tags : k => v if v != null } :
          "${path}.${k} = \"${v}\" is not one of: ${join(", ", var.resource_tags.allowed_values[k])}"
          if contains(keys(var.resource_tags.allowed_values), k) && !contains(lookup(var.resource_tags.allowed_values, k, []), v)
        ],
      )
    ]),
  ))
}

output "resource_tags" {
  description = "Tag manifest for .github/scripts/resource-tags.sh: every R2 bucket this layer owns, its ID, and the complete tag set it should carry. Read by the pipeline from state after apply, when the IDs are known."
  value = {
    account_id = var.cloudflare_account_id
    layer      = local.pipeline_tags.layer
    resources = [
      for key in sort(keys(local.r2_bucket_resource_tags)) : {
        address       = "r2_buckets.${key}"
        resource_type = "r2_bucket"
        # R2 uses the bucket name as its ID.
        resource_id = module.r2_buckets[key].bucket_id
        zone_id     = null
        tags        = local.r2_bucket_resource_tags[key]
      }
    ]
  }
}
