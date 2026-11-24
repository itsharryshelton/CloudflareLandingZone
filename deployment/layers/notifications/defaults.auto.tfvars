# Layer notifications - platform baseline. Auto-loaded from this directory.

# A policy is declared because somebody wants the alert. Off is a deliberate,
# per-policy statement in the account tree, never a silent default.
default_policy_enabled = true

# Any domain currently, recommend you set to your org's
allowed_email_domains = []

# Nothing is mandatory out of the box, because what an account is entitled to
# alert on depends on its plan and products. A platform that wants a baseline
# on every account lists it here - universal_ssl_event_type and incident_alert
# are available on every plan.
required_alert_types = []

# Alerts and the cf-webhook-auth secret should not cross the internet in clear.
allow_insecure_webhook_urls = false
