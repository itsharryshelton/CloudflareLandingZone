output "pages_projects" {
  description = "Per-project identity, keyed by the logical key. `subdomain` is the pages.dev hostname Cloudflare actually assigned - it differs from the name when the name was already taken on pages.dev, so read it from here."
  value       = { for key, project in module.pages_project : key => project.project }
}

output "pages_custom_domains" {
  description = "Per-project custom domain state. Anything but \"active\" some minutes after an apply usually means the CNAME is missing or unproxied."
  value       = { for key, project in module.pages_project : key => project.custom_domains }
}

output "pages_access_applications" {
  description = <<-EOT
    The hand-over to the zerotrust layer: one entry per project whose
    access_protection is not "none", shaped as an access_applications entry.
    Copy each into accounts/<account>/zerotrust.tfvars under the same key and
    add `policy_keys`. Until that is applied, nothing is protected - this layer
    cannot write or check Access.

    Re-read it after any apply that changes a project's custom domains. The
    zerotrust entry is a copy, and a hostname added here and not there is served
    without Access.
  EOT
  value       = local.access_applications
}
