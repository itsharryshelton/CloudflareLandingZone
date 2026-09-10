# Layer logpush - platform baseline. Auto-loaded from this directory.

# Must match the zones layer's default_zone_tier
default_zone_tier = "free"

# Zone Logpush is an Enterprise entitlement. A zone-scoped job on a lower plan fails the plan here rather than the apply at Cloudflare.
logpush_min_zone_tier = "enterprise"

# A job in logpush.tfvars pushes unless it says otherwise. The provider's own default is disabled.
default_logpush_job_enabled = true

# Every job lands in the same shape, so one SIEM parsing rule covers all of them.
default_logpush_output_type      = "ndjson"
default_logpush_timestamp_format = "rfc3339"

# Log4Shell lookup strings a client sent are defanged before they reach a downstream log processor.
default_cve_2021_44228_redaction = true

# Account datasets every account must push, e.g. ["audit_logs"]. Empty because Logpush is Enterprise-only and this layer runs for every account.
required_logpush_account_datasets = []

# Guardrails
allow_logpush_sampling              = false
allow_insecure_logpush_destinations = false
