# Account: account_a - Cloudflare Pages projects. Consumed by the pages layer only.
#
#   terraform -chdir=layers/pages plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/pages.tfvars
#
# The keys are state addresses, and `name` is the pages.dev subdomain requested.
# Renaming either destroys the project and every deployment in it.
#
# A custom domain here must not also be a record in dns.tfvars: this layer writes
# the CNAME itself, and two layers owning one record fight over it on every apply.
#
# Secrets are never written here. List the name under secret_names and put the
# value in the <account>-plan environment's TF_VAR_PAGES_PROJECT_SECRETS - see
# VARIABLES_AND_SECRETS.md.

pages_projects = {
  # A public documentation site, built by Cloudflare from Git. Production is
  # public; previews stay behind Access through the layer default
  # (access_protection = "previews"), so an unreleased branch is not.
  docs_site = {
    name = "account-a-docs"

    source = {
      type      = "github"
      owner     = "example-org"
      repo_name = "docs"
      # Only branches opened for review get a preview, not every scratch push.
      preview_deployment_setting = "custom"
      preview_branch_includes    = ["release/*", "docs/*"]
    }

    build = {
      build_command   = "npm run build"
      destination_dir = "dist"
      build_caching   = true
    }

    production = {
      env_vars = {
        # Read by the build and inlined into the page. Public by design.
        PUBLIC_SITE_URL = "https://docs.example.com"
      }
    }

    preview = {
      env_vars = {
        PUBLIC_SITE_URL = "https://preview.docs.example.com"
      }
    }

    custom_domains = [
      { hostname = "docs.example.com", zone_key = "primary" },
    ]
  }

  # An internal administration portal, deployed by Direct Upload from the
  # application's own pipeline. Every hostname it answers on - the custom
  # domain, the bare pages.dev hostname and every preview - must sit behind
  # Access, which is what "all" asks for. The matching zerotrust.tfvars entry is
  # `pages_admin_portal`, copied from this layer's pages_access_applications
  # output.
  admin_portal = {
    name              = "account-a-admin"
    access_protection = "all"

    production = {
      compatibility_date = "2026-09-01"
      # Closed, not open: if a Function behind the portal fails, serving the
      # static shell without it is the wrong failure.
      fail_open = false

      secret_names = ["SESSION_SECRET"]

      # IDs are pasted from the workers layer's outputs. This layer reads no
      # other state.
      kv_namespaces = {
        CONFIG = "00000000000000000000000000000000"
      }
      services = {
        TELEMETRY = { service = "account-a-telemetry" }
      }
    }

    # Previews get no bindings and no secrets: a build from any branch should
    # not be able to read production configuration.
    preview = {
      compatibility_date = "2026-09-01"
    }

    custom_domains = [
      { hostname = "admin.example.com", zone_key = "primary" },
    ]
  }
}
