# Layer pages - platform baseline. Auto-loaded from this directory.

default_production_branch = "main"

# Every branch pushed gets a preview. That is what makes Pages useful for review,
# and what makes the access default below matter.
default_preview_deployment_setting = "all"

# Every preview is published on *.<project>.pages.dev and is public by default -
# including branches nobody meant to show anyone. Asking for Access on previews
# is the baseline; a project states "all" for an internal portal, or "none" with
# the gate below.
default_access_protection = "previews"

# A public preview of an unreleased branch is a disclosure, not a diff. Opening one
# up takes a pull request that says why.
allow_unprotected_previews = false

# A custom domain with no CNAME sits at "pending" forever and nothing says so.
# Set true only where the record is genuinely managed elsewhere, e.g. a zone on
# another account.
allow_unmanaged_pages_hostnames = false

# Plain env vars are readable in the dashboard, the API and every plan of this
# layer. A credential belongs in secret_names.
allow_credential_like_plain_env_vars = false
