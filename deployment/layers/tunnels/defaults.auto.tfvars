# Layer tunnels - platform baseline. Auto-loaded from this directory.

# Remotely managed, so the ingress rules in this repository are the ones every connector runs and a dashboard edit shows up as drift.
default_tunnel_config_src = "cloudflare"

# Unmatched requests get a 404 rather than falling through to a real service.
default_catch_all_service = "http_status:404"

# Guardrails
allow_no_tls_verify                = false
allow_unmanaged_tunnel_hostnames   = false
allow_default_tunnel_route         = false
allow_public_tunnel_route_prefixes = false
