# Layer certificates - platform baseline. Auto-loaded from this directory.

# Certificate packs. txt is the one method that also covers wildcards, needs no origin change, and is published by Cloudflare
# itself on a full DNS setup. 90 days is the one period every CA offers, and Cloudflare renews packs itself.
default_certificate_authority = "google"
default_validation_method     = "txt"
default_validity_days         = 90

# Custom certificates: the chain most likely to verify on old clients.
default_bundle_method = "ubiquitous"

# Origin CA. Cloudflare defaults to 15 years; a year bounds how long a leaked origin key stays useful. Cloudflare sends no
# expiry notice, so whoever raises this should also say who does the rotation.
default_origin_ca_validity_days = 365
