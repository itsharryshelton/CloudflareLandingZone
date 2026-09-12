# Layer workers - platform baseline. Auto-loaded from this directory.

# Where the layer looks for Worker source and KV data files.
worker_source_dir = "scripts"
kv_data_dir       = "data/kv"

# Runtime pin.
default_compatibility_date  = "2026-01-01"
default_compatibility_flags = []

# Billing and placement stay at the account default.
default_usage_model    = null
default_placement_mode = null

# Logpush not in use yet
default_logpush = false

# Workers Logs on by default
default_observability = {
  enabled         = true
  logs_enabled    = true
  invocation_logs = true
}

# How many KV pairs Terraform will own in one namespace. This is a limit on
# Terraform, not on KV: each managed pair is a resource in state, a line in every
# plan and an API call on every apply. A dataset belongs in a
# `wrangler kv bulk put` step against the namespace_id this layer outputs.
default_max_managed_kv_pairs = 500

# D1 placement and replication stay at the account default
default_d1_primary_location_hint = null
default_d1_read_replication_mode = null

# Queue retention stays at Cloudflare's four days
default_queue_message_retention_period = null

# Guardrails
allow_inline_secret_text          = false
allow_unpinned_compatibility_date = false
allow_disabled_observability      = false

allow_queues_without_consumer                  = false
allow_queue_consumer_without_dead_letter_queue = false
allow_replicated_d1_in_jurisdiction            = false
