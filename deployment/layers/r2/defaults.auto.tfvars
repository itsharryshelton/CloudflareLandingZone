# Layer r2 - platform baseline. Auto-loaded from this directory.

# Placement and residency. Null lets Cloudflare place each bucket near its first write.
# Set default_bucket_location (e.g. "weur") to land the fleet in one region.
# Set default_jurisdiction (e.g. "eu") where residency is a regulatory requirement rather than a latency preference - the latter cannot be changed after a bucket is created.

default_bucket_location = null
default_jurisdiction    = null
default_storage_class   = "Standard"

# Cloudflare's own default here is 1.0.
default_custom_domain_min_tls = "1.2"

# Applied to any bucket that declares no lifecycle_rules of its own. A bucket that sets lifecycle_rules = [] opts out.
default_lifecycle_rules = [
  {
    id                                 = "abort-incomplete-multipart-uploads"
    prefix                             = ""
    abort_multipart_uploads_after_days = 7
  },
]

# Guardrails
allow_public_r2_dev_domains     = false
allow_wildcard_cors_origins     = false
allow_bucket_wide_object_expiry = false
