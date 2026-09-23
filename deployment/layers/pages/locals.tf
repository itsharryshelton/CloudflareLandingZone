# Applies the platform baseline, resolves zone keys to IDs, and derives the
# preflight assertions, so that pages.tf reads as a plain module call.

locals {
  # Only zones a custom domain actually targets are looked up, so a deployment
  # served only on pages.dev costs no API call.
  referenced_zone_keys = distinct(flatten([
    for project in var.pages_projects : [for domain in project.custom_domains : domain.zone_key if domain.zone_key != null]
  ]))

  referenced_zones = {
    for key, zone in var.zones : key => zone
    if contains(local.referenced_zone_keys, key)
  }

  # Module inputs. `production` and `preview` are passed whole: the module's
  # type has no `secret_names`, and Terraform drops an attribute the target
  # object type does not declare.
  projects = {
    for key, project in var.pages_projects : key => {
      name              = project.name
      production_branch = coalesce(project.production_branch, var.default_production_branch)

      git_source = project.source == null ? null : merge(project.source, {
        preview_deployment_setting = coalesce(project.source.preview_deployment_setting, var.default_preview_deployment_setting)
      })
      build_config = project.build

      deployment_configs = {
        production = project.production
        preview    = project.preview
      }
      secret_names = {
        production = project.production.secret_names
        preview    = project.preview.secret_names
      }

      custom_domains = [
        for domain in project.custom_domains : {
          hostname = lower(trimspace(domain.hostname))
          zone_id  = domain.zone_key == null ? null : try(data.cloudflare_zone.this[domain.zone_key].id, null)
        }
      ]

      access_protection = coalesce(project.access_protection, var.default_access_protection)
    }
  }

  # Derived assertions, consumed by preflight.tf.

  dangling_zone_keys = sort(distinct(flatten([
    for key, project in var.pages_projects : [
      for index, domain in project.custom_domains : "pages_projects.${key}.custom_domains[${index}] -> zone_key = \"${domain.zone_key}\""
      if domain.zone_key == null ? false : !contains(keys(var.zones), domain.zone_key)
    ]
  ])))

  # Cloudflare would add the domain to the project, then refuse the record,
  # leaving a hostname the project claims and nothing resolves to.
  hostnames_outside_zone = sort(flatten([
    for key, project in var.pages_projects : [
      for index, domain in project.custom_domains :
      "pages_projects.${key}.custom_domains[${index}]: \"${domain.hostname}\" is not within \"${var.zones[domain.zone_key].domain_name}\""
      if domain.zone_key == null ? false : (
        contains(keys(var.zones), domain.zone_key)
        ? !(
          lower(trimspace(domain.hostname)) == lower(var.zones[domain.zone_key].domain_name)
          || endswith(lower(trimspace(domain.hostname)), ".${lower(var.zones[domain.zone_key].domain_name)}")
        )
        : false
      )
    ]
  ]))

  unmanaged_hostnames = var.allow_unmanaged_pages_hostnames ? [] : sort(flatten([
    for key, project in var.pages_projects : [
      for index, domain in project.custom_domains : "pages_projects.${key}.custom_domains[${index}] (${domain.hostname})"
      if domain.zone_key == null
    ]
  ]))

  # pages.dev is one namespace, so two keys asking for one name cannot both get
  # it - the second is suffixed, and nothing here would say which is which.
  duplicate_project_names = sort([
    for name, claimants in {
      for key, project in var.pages_projects : lower(trimspace(project.name)) => key...
    } : "\"${name}\" (${join(", ", sort(claimants))})" if length(claimants) > 1
  ])

  # A hostname can be a custom domain of one project only; Cloudflare refuses
  # the second at apply, after the plan was approved.
  duplicate_hostnames = sort([
    for hostname, claimants in {
      for pair in flatten([
        for key, project in local.projects : [for domain in project.custom_domains : { hostname = domain.hostname, key = key }]
      ]) : pair.hostname => pair.key...
    } : "${hostname} (${join(", ", sort(claimants))})" if length(claimants) > 1
  ])

  # A Direct Upload project has no preview setting and still takes previews:
  # `wrangler pages deploy --branch=<anything>` publishes one.
  unprotected_previews = var.allow_unprotected_previews ? [] : sort([
    for key, project in local.projects : key
    if project.access_protection == "none" && (project.git_source == null ? true : project.git_source.preview_deployment_setting != "none")
  ])

  # Names only. The variable is sensitive as a whole, so its keys are unmarked
  # once, here, and every check below works from this.
  secret_keys = nonsensitive({
    for key, secrets in var.pages_project_secrets : key => {
      production = keys(secrets.production)
      preview    = keys(secrets.preview)
    }
  })

  environments = ["production", "preview"]

  missing_secrets = sort(flatten([
    for key, project in local.projects : [
      for env in local.environments : [
        for name in project.secret_names[env] : "${key}.${env}.${name}"
        if !contains(try(local.secret_keys[key][env], []), name)
      ]
    ]
  ]))

  orphaned_secrets = sort(flatten([
    for key, envs in local.secret_keys : [
      for env in local.environments : [
        for name in envs[env] : "${key}.${env}.${name}"
        if !contains(try(local.projects[key].secret_names[env], []), name)
      ]
    ]
  ]))

  # Prefixes the common frameworks inline into client-side JavaScript at build
  # time. A value under one of these is published, whatever type it was sent as.
  public_prefix_pattern = "^(VITE_|NEXT_PUBLIC_|PUBLIC_|REACT_APP_|GATSBY_|NUXT_PUBLIC_|EXPO_PUBLIC_|VUE_APP_|STORYBOOK_)"

  public_prefixed_secrets = sort(flatten([
    for key, project in local.projects : [
      for env in local.environments : [
        for name in project.secret_names[env] : "${key}.${env}.${name}"
        if can(regex(local.public_prefix_pattern, upper(name)))
      ]
    ]
  ]))

  credential_like_plain_env_vars = var.allow_credential_like_plain_env_vars ? [] : sort(flatten([
    for key, project in var.pages_projects : [
      for env, config in { production = project.production, preview = project.preview } : [
        for name in keys(config.env_vars) : "${key}.${env}.${name}"
        if can(regex("(SECRET|TOKEN|PASSWORD|PASSWD|API_?KEY|PRIVATE_?KEY|CREDENTIAL|CLIENT_SECRET)", upper(name)))
      ]
    ]
  ]))

  # The hand-over to the zerotrust layer. Built from the module's reported
  # hostnames, which use the subdomain Cloudflare actually assigned.
  access_hostnames = {
    for key, project in local.projects : key => (
      project.access_protection == "previews"
      ? module.pages_project[key].access_destinations.previews
      : module.pages_project[key].access_destinations.all
    )
    if project.access_protection != "none"
  }

  access_applications = {
    for key, hostnames in local.access_hostnames : "pages_${key}" => {
      name               = local.projects[key].access_protection == "previews" ? "Pages previews - ${local.projects[key].name}" : "Pages - ${local.projects[key].name}"
      domain             = hostnames[0]
      extra_destinations = [for uri in slice(hostnames, 1, length(hostnames)) : { uri = uri }]
    }
  }
}
