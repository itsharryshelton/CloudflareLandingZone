# Layer wan - platform baseline. Auto-loaded from this directory.

# Health checks are what make failover work: Cloudflare withdraws an unhealthy tunnel from the routing table, so traffic moves to the next route for the prefix.
# Declared for every tunnel rather than left to Cloudflare's default, so switching one off in the dashboard shows up as drift.
default_tunnel_health_check_enabled   = true
default_tunnel_health_check_rate      = "mid"
default_tunnel_health_check_type      = "reply"
default_tunnel_health_check_direction = "unidirectional"

# Null leaves Cloudflare's own defaults alone. Cloudflare's GRE MTU is 1476
default_gre_tunnel_ttl           = null
default_ipsec_replay_protection  = null
default_automatic_return_routing = null

# Two routes for one prefix at the same priority load-share across both tunnels. Give the standby a higher number where one path is genuinely preferred.
default_static_route_priority = 100

# Guardrails
allow_tunnels_without_health_checks       = false
allow_default_static_route                = false
allow_public_static_route_prefixes        = false
allow_single_tunnel_prefixes              = false
allow_static_routes_to_unmanaged_nexthops = false
