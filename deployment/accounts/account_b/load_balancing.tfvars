# Account: account_b - load balancers. Consumed by the load_balancing layer only.
#
#   terraform -chdir=layers/load_balancing plan \
#     -var-file=../../accounts/account_b/account.tfvars \
#     -var-file=../../accounts/account_b/zones.tfvars \
#     -var-file=../../accounts/account_b/load_balancing.tfvars
#
# lb_hostname must sit inside the referenced zone's domain; the layer fails the plan if it does not, rather than letting Cloudflare reject it after the monitor and pool already exist.
#
# health_check fields left unset fall back to default_health_check in layers/load_balancing/defaults.auto.tfvars.

load_balancers = {
  shop = {
    zone_key    = "primary"
    lb_hostname = "shop.example.net"

    # Latency steering rather than plain failover, and two healthy origins required
    # before the pool is considered up.
    steering_policy      = "dynamic_latency"
    session_affinity     = "cookie"
    pool_minimum_origins = 2

    origins = [
      { name = "shop-a", address = "shop-a.example.net", weight = 0.5 },
      { name = "shop-b", address = "shop-b.example.net", weight = 0.5 },
      # Host header override so a shared origin routes to the right vhost.
      { name = "shop-c", address = "shared.example.net", weight = 0.5, header_host = ["shop.example.net"] },
    ]

    health_check = {
      path     = "/health"
      interval = 30
      retries  = 3
    }
  }
}
