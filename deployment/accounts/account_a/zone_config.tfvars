# Account: Your-Org - zone configuration. Consumed by the zones layer only.
#
#   terraform -chdir=layers/zones plan \
#     -var-file=../../accounts/your-org/account.tfvars \
#     -var-file=../../accounts/your-org/zones.tfvars \
#     -var-file=../../accounts/your-org/zone_config.tfvars
#
# Keys must match zones.tfvars
#
# What belongs here, per zone:
#   zone_type            full | partial | secondary | internal
#   paused               true stops Cloudflare proxying the whole zone
#   ssl_mode             off | flexible | full | strict
#   min_tls_version      1.0 | 1.1 | 1.2 | 1.3
#   tls_1_3              on | off | zrt  (zrt adds 0-RTT; only for idempotent origins)
#   always_use_https     on | off
#   zone_settings        extra setting_id => value pairs, merged over the defaults
#   manage_subscription  BILLING - lets Terraform move this zone's rate plan
#   bot_management       replaces the account-wide default wholesale

zone_config = {
  primary = {
    # Example of how to override the defaults applied by layers/zones/defaults.auto.tfvars
    ssl_mode         = "full"
    min_tls_version  = "1.2"
    always_use_https = "on"
    security_level   = "medium"
  }
}
