# Layer zones - platform baseline. Auto-loaded from this directory.

# TLS posture for every zone that does not override it.
default_ssl_mode        = "strict"
default_min_tls_version = "1.2"

# Additions on top of the zone_base module's secure baseline, which already sets
# always_use_https, tls_1_3, automatic_https_rewrites, opportunistic_encryption,
# browser_check and http3.
default_zone_settings = {
  security_level = "medium"
  websockets     = "on"
}
