# Account: account_a - load balancers. Consumed by the load_balancing layer only.
#
#   terraform -chdir=layers/load_balancing plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/load_balancing.tfvars
#
# lb_hostname must sit inside the referenced zone's domain; the layer fails the plan if it does not, rather than letting Cloudflare reject it after the monitor and pool already exist.
#
# health_check fields left unset fall back to default_health_check in layers/load_balancing/defaults.auto.tfvars.

load_balancers = {
  app = {
    zone_key    = "primary"
    lb_hostname = "app.example.com"

    origins = [
      { name = "primary-westeurope", address = "we-app.example.net", weight = 0.7 },
      { name = "failover-northeurope", address = "ne-app.example.net", weight = 0.3 },
    ]

    # Only the path differs from the policy.
    health_check = {
      path = "/api/health/readiness"
    }
  }
}
