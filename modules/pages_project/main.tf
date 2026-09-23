# One Cloudflare Pages project, its custom domains, and the CNAME behind each
# domain where the zone is known.
#
# WHAT TERRAFORM CANNOT DO HERE
# It declares the project. It does not deploy one: a Git-sourced project builds
# on push, and a Direct Upload project waits for `wrangler pages deploy` from a
# pipeline this module knows nothing about. An apply that creates a project
# leaves a hostname serving nothing until the first deployment lands.
#
# It also does not put Access in front of anything. That belongs to the
# zerotrust layer and its token; see the `access_destinations` output for the
# exact hostnames to hand it.
resource "cloudflare_pages_project" "this" {
  account_id        = var.account_id
  name              = var.name
  production_branch = var.production_branch

  build_config = var.git_source == null || var.build_config == null ? null : {
    build_command   = var.build_config.build_command
    destination_dir = var.build_config.destination_dir
    root_dir        = var.build_config.root_dir
    build_caching   = var.build_config.build_caching
  }

  source = var.git_source == null ? null : {
    type = var.git_source.type
    config = {
      owner     = var.git_source.owner
      repo_name = var.git_source.repo_name
      # Cloudflare holds the branch in two places. Sent once from one input so
      # the two cannot disagree about which deployments are production.
      production_branch              = var.production_branch
      production_deployments_enabled = var.git_source.production_deployments_enabled
      pr_comments_enabled            = var.git_source.pr_comments_enabled
      preview_deployment_setting     = var.git_source.preview_deployment_setting
      preview_branch_includes        = length(var.git_source.preview_branch_includes) == 0 ? null : var.git_source.preview_branch_includes
      preview_branch_excludes        = length(var.git_source.preview_branch_excludes) == 0 ? null : var.git_source.preview_branch_excludes
      path_includes                  = length(var.git_source.path_includes) == 0 ? null : var.git_source.path_includes
      path_excludes                  = length(var.git_source.path_excludes) == 0 ? null : var.git_source.path_excludes
    }
  }

  deployment_configs = local.deployment_configs

  lifecycle {
    precondition {
      condition     = length(local.plain_and_secret) == 0
      error_message = "These names are declared as both a plain env var and a secret: ${join("; ", local.plain_and_secret)}. Cloudflare keeps one value per name, so one of the two is silently discarded. Keep the secret and remove the plain entry."
    }

    precondition {
      condition     = length(local.binding_collisions) == 0
      error_message = "These names are used by more than one binding in the same environment: ${join("; ", local.binding_collisions)}. A Function reads every binding as env.<NAME>, so only one of them would be reachable."
    }
  }
}

# The API adds the domain to the project. It does not create the DNS record -
# see cloudflare_dns_record below - and until one resolves to the project the
# domain stays "pending" and no certificate is issued.
resource "cloudflare_pages_domain" "this" {
  for_each = local.custom_domains

  account_id   = var.account_id
  project_name = cloudflare_pages_project.this.name
  name         = each.key
}

resource "cloudflare_dns_record" "this" {
  for_each = { for hostname, domain in local.custom_domains : hostname => domain if domain.zone_id != null }

  zone_id = each.value.zone_id
  name    = each.key
  type    = "CNAME"
  # The real pages.dev hostname, which is the project name only if nobody else
  # on Cloudflare had it first.
  content = cloudflare_pages_project.this.subdomain
  ttl     = 1
  # Proxied, so the zone's WAF and any Access application on the hostname see
  # the request. Unproxied would still serve, and bypass both.
  proxied = true
  comment = "Cloudflare Pages custom domain for ${var.name}. Managed by Terraform."
}
