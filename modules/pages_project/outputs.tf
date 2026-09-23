output "project" {
  description = "Project identity. `subdomain` is the pages.dev hostname Cloudflare actually assigned, which carries a random suffix when the name was already taken elsewhere on pages.dev - anything that points at the project must use this, not the name."
  value = {
    id                = cloudflare_pages_project.this.id
    name              = cloudflare_pages_project.this.name
    subdomain         = cloudflare_pages_project.this.subdomain
    production_branch = cloudflare_pages_project.this.production_branch
    domains           = cloudflare_pages_project.this.domains
    created_on        = cloudflare_pages_project.this.created_on
    git_source        = var.git_source == null ? null : "${var.git_source.type}:${var.git_source.owner}/${var.git_source.repo_name}"
  }
}

output "custom_domains" {
  description = "Hostname => activation state. `status` other than \"active\" after an apply usually means the CNAME is missing or unproxied; `dns_managed` says whether this module owns that record."
  value = {
    for hostname, domain in cloudflare_pages_domain.this : hostname => {
      status                = domain.status
      certificate_authority = domain.certificate_authority
      dns_managed           = contains(keys(cloudflare_dns_record.this), hostname)
    }
  }
}

output "access_destinations" {
  description = <<-EOT
    The hostnames an Access application has to list to protect this project.

    - `previews` - "*.<subdomain>": every branch and commit preview. It does NOT
                   match the bare <subdomain>, which serves production.
    - `all`      - Every custom domain, the bare <subdomain>, and the preview
                   wildcard. Protecting only the custom domain leaves production
                   reachable, unauthenticated, on pages.dev.
  EOT
  value = {
    previews = ["*.${cloudflare_pages_project.this.subdomain}"]
    all = concat(
      sort(keys(local.custom_domains)),
      [cloudflare_pages_project.this.subdomain, "*.${cloudflare_pages_project.this.subdomain}"],
    )
  }
}
