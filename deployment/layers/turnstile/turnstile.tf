# Cloudflare Turnstile widgets.
#
# Its own layer rather than part of waf, because a widget is not a rule and is
# not zone-scoped: it is a key pair plus a hostname list, consumed by a page and
# a backend that Terraform does not manage. Nothing else in this repository
# reads it, and it reads nothing - which is the point. An apply here can never
# propose a change to a zone, a ruleset or a DNS record.
#
# It also means the layer cannot verify the thing that actually matters. Whether
# a form is protected depends on the sitekey pasted into the page and the secret
# configured in the backend, and neither is visible from here. See outputs.tf
# for the values to hand over, and imports.tf before a first apply.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//turnstile?ref=v1.0.0"
module "turnstile" {
  source = "git::https://github.com/Your-Org/cloudflare-platform-modules//turnstile"

  account_id = var.cloudflare_account_id

  widgets                = local.widgets
  max_domains_per_widget = var.max_domains_per_widget
}
