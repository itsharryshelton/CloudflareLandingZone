output "turnstile_sitekeys" {
  description = "Logical key => sitekey. This is the handover: the value each page must embed for its form to be protected by the widget declared here. Nothing in this repository can check that it has been done, so a sitekey that appears here and nowhere in the site is a widget protecting nothing. Public by design - it is served to every visitor."
  value       = module.turnstile.sitekeys
}

output "turnstile_domain_coverage" {
  description = "Hostname => the widget key covering it. Subdomains are not listed: an entry for \"example.com\" also covers \"www.example.com\". This answers \"which sitekey should this page be embedding\" without opening the dashboard."
  value       = module.turnstile.domain_coverage
}

output "turnstile_widgets" {
  description = "Full per-widget record: id, sitekey, mode, hostnames, region and Cloudflare's own `deployed_via` / `last_modified_via`. Those last two are the drift signal - anything but \"api\" means the widget was last touched in the dashboard or by wrangler rather than by this pipeline."
  value       = module.turnstile.widgets
}

# Deliberately not exported.
#
# The backend's /siteverify secret is in module.turnstile.secrets, and it is in
# this layer's state either way. Re-exporting it here would put it in the root
# outputs, which is what a pipeline artefact, a `terraform output` in a log and a
# state consumer all read. Read one deliberately when handing it over:
#
#   terraform output -json -state=... | jq -r '.turnstile_widget_secrets.value.primary'
#
# and if that is ever needed routinely, the answer is a secrets manager, not an
# output. Rotating a secret is not possible in place: a new secret means a new
# widget, which means a new sitekey and a redeploy of every page that embeds it.
