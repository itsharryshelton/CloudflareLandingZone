# Layer turnstile - platform baseline. Auto-loaded from this directory.

# Cloudflare's own recommendation, and the mode that fails visibly: a visitor who
# has to click knows something happened. A widget states its own mode when it needs one.
default_widget_mode = "managed"

# "china" is a separate widget network for mainland performance and cannot be changed
# after creation, so it has to be a per-widget decision, never a silent default.
default_widget_region = "world"

# Cloudflare's Enterprise ceiling. A hostname already covers its subdomains, so a widget
# approaching this is usually listing subdomains it does not need to.
max_domains_per_widget = 200

# Off-label removes Cloudflare branding. Turning it on is a contractual and design
# decision, not a Terraform one - so it takes a pull request that says why.
allow_offlabel_widgets = false

# Invisible mode runs with nothing on the page telling the visitor a challenge happened,
# which is why Cloudflare requires the privacy addendum before it is used.
invisible_mode_privacy_addendum_accepted = false
