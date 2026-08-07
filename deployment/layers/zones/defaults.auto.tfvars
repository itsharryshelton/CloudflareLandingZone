# Layer zones - platform baseline. Auto-loaded from this directory.

# TLS posture for every zone that does not override it.
default_ssl_mode        = "strict"
default_min_tls_version = "1.2"

# TLS 1.3 on, but without 0-RTT and always use HTTPS
default_tls_1_3          = "on"
default_always_use_https = "on"

# Additions on top of the zone_base module's secure baseline
default_zone_settings = {
  security_level = "medium"
  websockets     = "on"
}

# Zone tier default, using free to avoid any billing costs if manage_zone_subscriptions is true
default_zone_tier = "free"

# BILLING. Leave false unless you intend Terraform to buy and sell Cloudflare plans.
manage_zone_subscriptions      = false
default_subscription_frequency = "monthly" # Can be changed to annual if required
