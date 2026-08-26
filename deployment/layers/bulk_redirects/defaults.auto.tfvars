# Layer bulk_redirects - platform baseline. Auto-loaded from this directory.

# Terraform owns the list and the rule; the pipeline loads the rows.
#
# Cloudflare replaces a list wholesale on every write, so a managed row is in
# state, in every plan and in every apply. A list opts in with
# manage_items = true where its rows genuinely belong in a pull request.
default_manage_items      = false
default_max_managed_items = 500

# Row defaults.
#
# 301 matches Cloudflare's default. Note it is close to irreversible in practice
# - browsers cache it hard - so use 302 while a migration is still being proven.
default_status_code = 302

# Cloudflare's own default here is false. True keeps campaign and attribution
# parameters alive across a redirect, which is usually how a broken old URL gets
# reported in the first place.
default_preserve_query_string = true

# Dashboard label for the account's http_request_redirect entry-point ruleset.
ruleset_name = "Bulk Redirects"

# Guardrails
#
# The two ceilings are the Enterprise default quotas. Cloudflare enforces them at
# apply time, item by item, so an over-quota plan applies part way and then fails.
max_bulk_redirect_lists = 25
max_bulk_redirect_rules = 50

allow_hostnames_outside_zone_inventory = false
allow_unreferenced_lists               = false
