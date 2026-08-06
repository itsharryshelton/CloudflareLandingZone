# Layer zerotrust - platform baseline. Auto-loaded from this directory.

# Session lengths. Shorter is safer.
default_session_duration           = "24h"
default_warp_auth_session_duration = "24h"

# Cloudflare's minimum. It is what stops a leaver holding a seat indefinitely.
user_seat_expiration_inactive_time = "730h"

# A year. Long enough not to break an unattended system, short enough to force a rotation into somebody's plan.
default_service_token_duration = "8760h"

# Policy decisions this layer refuses - bypass removes authentication entirely from every application the policy is attached to.
restricted_policy_decisions = ["bypass"]

# Domains an Access include rule may admit, for example ["example.com"]. Empty allows any domain.
allowed_email_domains = []

# Lock the Zero Trust dashboard to read-only, making this repository the only
# route to an Access change. Off by default because an account still being built
# needs the dashboard. Turn it on once the account is steady.
lock_dashboard_to_read_only = false

# Send users straight to the only login method that makes sense.
auto_redirect_to_identity = false

# Let a WARP-enrolled device authenticate without a browser login.
allow_authenticate_via_warp = false

allow_team_name_change = false
