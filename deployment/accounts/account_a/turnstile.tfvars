# Account: account_a - Cloudflare Turnstile widgets. Consumed by the turnstile layer only.
#
#   terraform -chdir=layers/turnstile plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/turnstile.tfvars
#
# Widgets are account-scoped, not zone-scoped. Nothing here has to match a key in
# zones.tfvars, and the layer never reads that file - Cloudflare treats the hostname
# list as free text, so a typo produces a widget that silently refuses to render
# rather than an error at apply.
#
# A hostname covers its own subdomains, so the apex entries below already serve www.
#
# The keys are state addresses. Renaming one destroys and recreates the widget,
# which issues a new sitekey and breaks every page still carrying the old one.

turnstile_widgets = {
  # One widget per set of hostnames that may share a secret: whoever holds the
  # secret can validate a token for every hostname the widget lists. A staging
  # site therefore belongs on its own widget - but only if it sits on its own
  # apex, because listing "example.com" here already covers "staging.example.com".
  primary = {
    name = "Primary site (example.com)"
    domains = [
      "example.com",
    ]
    mode = "managed"
  }

  # Several hostnames on one widget is the right shape when one backend validates
  # all of them - the regional storefronts of a single application, not unrelated
  # sites that happen to be on the same account.
  marketing = {
    name = "Marketing sites"
    domains = [
      "example.net",
      "example.org",
    ]
    mode = "managed"
  }
}
