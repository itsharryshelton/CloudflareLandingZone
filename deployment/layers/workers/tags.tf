# Cloudflare resource tags for the KV namespaces, D1 databases, queues and
# Workers this layer owns.
#
# The provider has no tagging resource yet, so nothing here calls the Tagging
# API. This resolves each resource's complete tag set from var.resource_tags and
# outputs it with the resource ID; .github/scripts/resource-tags.sh applies it
# after the apply, from a job holding a token of its own. The precedence rules
# are in accounts/<account>/tags.tfvars.
#
# Workers deployed with wrangler from their own repositories are not in this
# layer's state, so they are not tagged from here.
#
# When the provider ships a tagging resource, for_each it over the four
# *_resource_tags locals here and retire the script.

locals {
  # Merged last, so an account tree cannot make a resource read as unmanaged or
  # as another layer's.
  pipeline_tags = {
    "managed-by" = "terraform"
    layer        = basename(abspath(path.module))
  }

  # Every namespace, database, queue and Worker, not only those tags.tfvars
  # lists: the pipeline keys are what a `tag=!managed-by` filter relies on to
  # find one somebody created by hand.
  kv_namespace_resource_tags = {
    for key in keys(var.kv_namespaces) : key => {
      for k, v in merge(
        var.resource_tags.defaults,
        var.resource_tags.kv_namespaces.defaults,
        lookup(var.resource_tags.kv_namespaces.resources, key, {}),
        local.pipeline_tags,
      ) : k => v if v != null
    }
  }

  d1_database_resource_tags = {
    for key in keys(var.d1_databases) : key => {
      for k, v in merge(
        var.resource_tags.defaults,
        var.resource_tags.d1_databases.defaults,
        lookup(var.resource_tags.d1_databases.resources, key, {}),
        local.pipeline_tags,
      ) : k => v if v != null
    }
  }

  queue_resource_tags = {
    for key in keys(var.queues) : key => {
      for k, v in merge(
        var.resource_tags.defaults,
        var.resource_tags.queues.defaults,
        lookup(var.resource_tags.queues.resources, key, {}),
        local.pipeline_tags,
      ) : k => v if v != null
    }
  }

  worker_script_resource_tags = {
    for key in keys(var.worker_scripts) : key => {
      for k, v in merge(
        var.resource_tags.defaults,
        var.resource_tags.worker_scripts.defaults,
        lookup(var.resource_tags.worker_scripts.resources, key, {}),
        local.pipeline_tags,
      ) : k => v if v != null
    }
  }

  # Preflight checks here. The shared settings and this layer's own sections
  # only - another layer's section is that layer's to report.
  resource_tag_sources = merge(
    { "resource_tags.defaults" = var.resource_tags.defaults },
    { "resource_tags.kv_namespaces.defaults" = var.resource_tags.kv_namespaces.defaults },
    { "resource_tags.d1_databases.defaults" = var.resource_tags.d1_databases.defaults },
    { "resource_tags.queues.defaults" = var.resource_tags.queues.defaults },
    { "resource_tags.worker_scripts.defaults" = var.resource_tags.worker_scripts.defaults },
    { for key, tags in var.resource_tags.kv_namespaces.resources : "resource_tags.kv_namespaces.resources.${key}" => tags },
    { for key, tags in var.resource_tags.d1_databases.resources : "resource_tags.d1_databases.resources.${key}" => tags },
    { for key, tags in var.resource_tags.queues.resources : "resource_tags.queues.resources.${key}" => tags },
    { for key, tags in var.resource_tags.worker_scripts.resources : "resource_tags.worker_scripts.resources.${key}" => tags },
  )

  resource_tag_problems = sort(concat(
    [
      for key in keys(var.resource_tags.kv_namespaces.resources) : "resource_tags.kv_namespaces.resources.${key} names no namespace in var.kv_namespaces"
      if !contains(keys(var.kv_namespaces), key)
    ],
    [
      for key in keys(var.resource_tags.d1_databases.resources) : "resource_tags.d1_databases.resources.${key} names no database in var.d1_databases"
      if !contains(keys(var.d1_databases), key)
    ],
    [
      for key in keys(var.resource_tags.queues.resources) : "resource_tags.queues.resources.${key} names no queue in var.queues"
      if !contains(keys(var.queues), key)
    ],
    [
      for key in keys(var.resource_tags.worker_scripts.resources) : "resource_tags.worker_scripts.resources.${key} names no Worker in var.worker_scripts"
      if !contains(keys(var.worker_scripts), key)
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
  description = "Tag manifest for .github/scripts/resource-tags.sh: every KV namespace, D1 database, queue and Worker this layer owns, its ID, and the complete tag set it should carry. Read by the pipeline from state after apply, when the IDs are known."
  value = {
    account_id = var.cloudflare_account_id
    layer      = local.pipeline_tags.layer
    resources = concat(
      [
        for key in sort(keys(local.kv_namespace_resource_tags)) : {
          address       = "kv_namespaces.${key}"
          resource_type = "kv_namespace"
          resource_id   = module.kv_namespaces[key].namespace_id
          zone_id       = null
          tags          = local.kv_namespace_resource_tags[key]
        }
      ],
      [
        for key in sort(keys(local.d1_database_resource_tags)) : {
          address       = "d1_databases.${key}"
          resource_type = "d1_database"
          resource_id   = module.d1_databases[key].database_id
          zone_id       = null
          tags          = local.d1_database_resource_tags[key]
        }
      ],
      [
        for key in sort(keys(local.queue_resource_tags)) : {
          address       = "queues.${key}"
          resource_type = "queue"
          # The tagging API takes the queue's ID, not its name.
          resource_id = module.queues[key].queue_id
          zone_id     = null
          tags        = local.queue_resource_tags[key]
        }
      ],
      [
        for key in sort(keys(local.worker_script_resource_tags)) : {
          address       = "worker_scripts.${key}"
          resource_type = "worker"
          # A Workers script's ID is its name.
          resource_id = module.worker_scripts[key].id
          zone_id     = null
          tags        = local.worker_script_resource_tags[key]
        }
      ],
    )
  }
}
