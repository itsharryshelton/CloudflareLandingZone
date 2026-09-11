# Layer device_posture - platform baseline. Auto-loaded from this directory.

# Cloudflare's own default, stated so it is visible and so the value in state matches what the API reports.
default_posture_schedule = "5m"

# How often Cloudflare polls a service provider. Shorter revokes a non-compliant device sooner and costs more third-party API calls.
default_integration_interval = "10m"

# A rule with no expiration keeps a device's last result until it reports again - so a device that stops reporting keeps its last pass.
# Derive one at twice the polling period, Cloudflare's own recommendation.
derive_posture_expiration = true

# A binary check without a signing thumbprint passes for any file at that path, whoever wrote it.
require_signed_binary_checks = true

# Rule types this layer refuses. Legacy Tanium is Access-only, invisible to Gateway, and superseded by tanium_s2s.
restricted_posture_rule_types = ["tanium"]
