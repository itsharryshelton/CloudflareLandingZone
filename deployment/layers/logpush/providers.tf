# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer:
#   Account  Logs:Edit - account-scoped jobs: audit_logs, gateway_*, and the
#                        other account datasets
#   Zone     Logs:Edit - zone-scoped jobs: http_requests, firewall_events, and
#                        the other zone datasets
#   Zone     Zone:Read - so data.cloudflare_zone can resolve a zone_key to its ID
#
# Cloudflare's own documentation calls Logs:Edit "Logs: Write"; it is one grant.
#
# Jobs on an Access, Gateway or DEX dataset - access_requests, gateway_dns,
# gateway_http, gateway_network, dex_application_tests, dex_device_state_events -
# need one more, and Cloudflare will not create, change or delete such a job
# without it:
#   Account  Zero Trust: PII Read
#
provider "cloudflare" {}
