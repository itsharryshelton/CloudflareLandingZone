# Layer origin_pulls - platform baseline. Auto-loaded from this directory.

# Zone-level Authenticated Origin Pulls is opt-in per zone, not inherited. Turning it on changes what the edge sends every origin in the zone.
default_zone_level_enabled = false

# Cloudflare's default client certificate is presented by the edge for EVERY customer on the platform, so an origin that trusts it
# accepts traffic proxied through any Cloudflare account, not only this one. Still a real filter in front of an origin that would
# otherwise accept anything, so it is allowed and a `check` warns on each zone using it. Set false where an origin is relied on to
# identify the tenant - then every zone must upload a certificate of its own.
allow_shared_cloudflare_certificate = true

# Cloudflare's public Origin Pull CA. Null uses ca/cloudflare_origin_pull_ca.pem in this layer; see ca/README.md to refresh it.
cloudflare_origin_pull_ca_certificate = null
