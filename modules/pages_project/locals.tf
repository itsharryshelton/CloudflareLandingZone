locals {
  environments = ["production", "preview"]

  # Secret names are not sensitive, only their values. Keying off the names
  # keeps the rest of deployment_configs readable in a plan; building the map
  # from the sensitive variable directly would mark the whole block sensitive
  # and hide every binding change behind "(sensitive value)".
  secret_names = {
    production = nonsensitive(keys(var.secret_env_vars.production))
    preview    = nonsensitive(keys(var.secret_env_vars.preview))
  }

  # Empty maps and lists are sent as null. The API omits an unset binding type
  # rather than returning {}, and a declared {} against an omitted field is a
  # diff on every plan.
  deployment_configs = {
    for env in local.environments : env => {
      compatibility_date                   = var.deployment_configs[env].compatibility_date
      compatibility_flags                  = length(var.deployment_configs[env].compatibility_flags) == 0 ? null : var.deployment_configs[env].compatibility_flags
      always_use_latest_compatibility_date = var.deployment_configs[env].always_use_latest_compatibility_date
      fail_open                            = var.deployment_configs[env].fail_open
      placement                            = var.deployment_configs[env].placement_mode == null ? null : { mode = var.deployment_configs[env].placement_mode }

      env_vars = (length(var.deployment_configs[env].env_vars) + length(local.secret_names[env])) == 0 ? null : merge(
        { for name, value in var.deployment_configs[env].env_vars : name => { type = "plain_text", value = value } },
        { for name in local.secret_names[env] : name => { type = "secret_text", value = var.secret_env_vars[env][name] } },
      )

      kv_namespaces   = length(var.deployment_configs[env].kv_namespaces) == 0 ? null : { for name, id in var.deployment_configs[env].kv_namespaces : name => { namespace_id = id } }
      d1_databases    = length(var.deployment_configs[env].d1_databases) == 0 ? null : { for name, id in var.deployment_configs[env].d1_databases : name => { id = id } }
      r2_buckets      = length(var.deployment_configs[env].r2_buckets) == 0 ? null : var.deployment_configs[env].r2_buckets
      services        = length(var.deployment_configs[env].services) == 0 ? null : var.deployment_configs[env].services
      queue_producers = length(var.deployment_configs[env].queue_producers) == 0 ? null : { for name, queue in var.deployment_configs[env].queue_producers : name => { name = queue } }
    }
  }

  custom_domains = { for domain in var.custom_domains : domain.hostname => domain }

  # Derived assertions, consumed by the preconditions in main.tf.

  # One name in both maps is sent twice, and which of the two the API keeps is
  # not something to find out in production.
  plain_and_secret = sort(flatten([
    for env in local.environments : [
      for name in local.secret_names[env] : "${env}.${name}"
      if contains(keys(var.deployment_configs[env].env_vars), name)
    ]
  ]))

  # Binding names share one namespace inside a Function: env.CONFIG is one thing.
  binding_collisions = sort(flatten([
    for env in local.environments : [
      for name, claimants in {
        for pair in flatten([
          for kind, names in {
            env_vars        = concat(keys(var.deployment_configs[env].env_vars), local.secret_names[env])
            kv_namespaces   = keys(var.deployment_configs[env].kv_namespaces)
            d1_databases    = keys(var.deployment_configs[env].d1_databases)
            r2_buckets      = keys(var.deployment_configs[env].r2_buckets)
            services        = keys(var.deployment_configs[env].services)
            queue_producers = keys(var.deployment_configs[env].queue_producers)
          } : [for n in distinct(names) : { name = n, kind = kind }]
        ]) : pair.name => pair.kind...
      } : "${env}.${name} (${join(", ", sort(claimants))})" if length(claimants) > 1
    ]
  ]))
}
