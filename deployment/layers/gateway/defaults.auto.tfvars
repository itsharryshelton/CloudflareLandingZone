# Layer gateway - platform baseline. Auto-loaded from this directory.

# Precedence below this belongs to the baseline catalogue in locals.gateway.tf.
# Gateway stops at the first allow or block that matches, so this is what keeps
# an account tree from putting a rule in front of a platform block.
reserved_precedence_ceiling = 100

# Gateway actions this layer refuses. Empty by default: "off" (Do Not Inspect)
# is the one worth thinking hardest about and it is also what a Microsoft 365
# deployment needs. Set ["off"] on an account where inspection is never to be
# turned off outside the baseline.
restricted_actions = []

# Storing the matched content of a DLP hit in Cloudflare's logs. 
# Off: the thing stored is the sensitive data the policy exists to protect.
allow_dlp_payload_logging = false

# DNSSEC validation is what stops a forged answer being accepted for a signed zone.
allow_disabling_dnssec_validation = false

# Serving a site whose certificate did not validate, with no warning and no log
# entry. An expired internal certificate and an interception attempt look the same.
allow_untrusted_certificate_pass_through = false

# Applied to every HTTP allow policy that sets nothing of its own, so a change
# made in the dashboard shows up as drift. One of pass_through, block, error.
default_untrusted_cert_action = "error"

# Cloudflare security category names for the baseline threat rules. Names, not
# IDs - the layer resolves them against the account at plan time, and an
# unrecognised one fails the plan listing what Cloudflare actually offers.
gateway_security_categories = [
  "Command and Control & Botnet",
  "Malware",
]

# Content categories are an acceptable-use decision rather than a security one,
# so there is no default that suits every customer. Set it per account.
gateway_blocked_content_categories = []

# Applications exempted from TLS inspection by the baseline bypass rule. Empty
# here on purpose: bypassing an application means nothing inside it is inspected
# or matched by a DLP profile, so it is an account-level decision.
gateway_bypass_applications = []

# DLP profile UUIDs are created per account in the Zero Trust dashboard, so they
# cannot have a platform default.
gateway_dlp_profile_ids = []

# File extensions the baseline quarantine rule detonates in Cloudflare's sandbox
# before delivering. Short on purpose - quarantine makes the user wait.
gateway_quarantine_file_types = []

# What a blocked user is told, and where to ask about it. The alternative is a
# ticket saying "the internet is broken" and somebody finding another network.
default_block_notification = {
  enabled = true
  msg     = "This request was blocked by your organisation's internet policy."
}
