resource "terraform_data" "preflight" {
  input = {
    pages_projects   = length(var.pages_projects)
    referenced_zones = length(local.referenced_zones)
    # Surfaced in the plan because it is the field a reviewer has to carry across
    # to the zerotrust layer by hand.
    access_protection = { for key, project in local.projects : key => project.access_protection }
  }

  lifecycle {
    precondition {
      condition     = length(local.dangling_zone_keys) == 0
      error_message = "zone_key does not match any entry in var.zones: ${join("; ", local.dangling_zone_keys)}. Valid keys: ${join(", ", sort(keys(var.zones)))}. Both layers must be given the same accounts/<account>/zones.tfvars."
    }

    precondition {
      condition     = length(local.hostnames_outside_zone) == 0
      error_message = "A custom domain is not inside the zone it references: ${join("; ", local.hostnames_outside_zone)}. Cloudflare would add the domain to the project, then refuse the DNS record, leaving it at \"pending\" with nothing resolving to it."
    }

    precondition {
      condition     = length(local.unmanaged_hostnames) == 0
      error_message = "These custom domains name no zone_key, so no CNAME will point at the project: ${join("; ", local.unmanaged_hostnames)}. Adding a domain through the API does not create the record, so it would sit at \"pending\" and never serve. Add the zone_key from zones.tfvars, or set allow_unmanaged_pages_hostnames = true in layers/pages/defaults.auto.tfvars if the record really is managed elsewhere."
    }

    precondition {
      condition     = length(local.duplicate_project_names) == 0
      error_message = "Two projects request the same name: ${join("; ", local.duplicate_project_names)}. pages.dev is a single namespace, so one would be given a random suffix and the two could not be told apart from their names."
    }

    precondition {
      condition     = length(local.duplicate_hostnames) == 0
      error_message = "These hostnames are a custom domain of more than one project: ${join("; ", local.duplicate_hostnames)}. Cloudflare refuses the second at apply, after the plan was approved."
    }

    precondition {
      condition     = length(local.unprotected_previews) == 0
      error_message = "These projects publish preview deployments with access_protection = \"none\": ${join(", ", local.unprotected_previews)}. Every branch pushed would be public on *.<project>.pages.dev, including work nobody meant to show. Set access_protection = \"previews\" (or \"all\") and add the entry from the pages_access_applications output to zerotrust.tfvars, set source.preview_deployment_setting = \"none\", or set allow_unprotected_previews = true in layers/pages/defaults.auto.tfvars on a pull request that says why."
    }

    precondition {
      condition     = length(local.missing_secrets) == 0
      error_message = "These secret_names have no value in TF_VAR_pages_project_secrets: ${join(", ", local.missing_secrets)}. Add them to the <account>-plan environment's TF_VAR_PAGES_PROJECT_SECRETS - see VARIABLES_AND_SECRETS.md. The plan, not apply, is what reads it."
    }

    precondition {
      condition     = length(local.orphaned_secrets) == 0
      error_message = "TF_VAR_pages_project_secrets holds values no project declares: ${join(", ", local.orphaned_secrets)}. A secret against the wrong key is a live credential sitting in an environment and doing nothing, while the project it was meant for runs without it. Add the name to that environment's secret_names, or remove the value."
    }

    # Not gated. There is no configuration in which this is safe.
    precondition {
      condition     = length(local.public_prefixed_secrets) == 0
      error_message = "These secrets use a prefix that front-end frameworks inline into the browser bundle at build time: ${join(", ", local.public_prefixed_secrets)}. The value would be served to every visitor in plain JavaScript, whatever type it was stored as. Rename it without the public prefix and read it only from a Pages Function."
    }

    precondition {
      condition     = length(local.credential_like_plain_env_vars) == 0
      error_message = "These plain env vars look like credentials: ${join(", ", local.credential_like_plain_env_vars)}. A plain value is readable in the dashboard, the API and every plan of this layer. Move it to secret_names and TF_VAR_PAGES_PROJECT_SECRETS, or, if it genuinely is not a secret, set allow_credential_like_plain_env_vars = true in layers/pages/defaults.auto.tfvars on a pull request that says why."
    }
  }
}
