# One Cloudflare AI Gateway and its dynamic routes.
#
# A gateway is a proxy between an application and its AI providers. It logs,
# caches, rate limits and applies DLP, guardrails and spend limits to every
# request sent through it. It is account-scoped and attached to no zone; a
# client reaches it by URL, built from the account ID and the gateway ID.
#
# WHAT TERRAFORM CANNOT DO HERE
# It declares the gateway. It does not point anything at it: an application
# only uses a gateway once its base URL is changed to the gateway's endpoint.
#
# It creates no credential either. Callers of an authenticated gateway need a
# Cloudflare token with AI Gateway Run, and a BYOK gateway needs provider keys
# in Secrets Store with a provider config attaching each one. Provider 5.23 has
# no resource for provider configs (cloudflare/terraform-provider-cloudflare#7332),
# and the Run token is the application's credential, not this pipeline's.
#
# Not managed, deliberately, and so left as the dashboard set them:
#   otel                    - exports every prompt and completion to a third-
#                             party collector. Its authorization is a Secrets
#                             Store reference in a format Cloudflare does not
#                             document, and its headers usually carry a
#                             credential the provider does not mark sensitive.
#   stripe                  - carries a Stripe credential, and is documented
#                             nowhere beyond the API schema.
#   workers_ai_billing_mode - provider 5.23 accepts only "postpaid", and sends
#                             it on every update whether set or not. A gateway
#                             switched to Unified Billing in the dashboard is
#                             switched back by the next apply that changes it
#                             (cloudflare/terraform-provider-cloudflare#7331,
#                             fixed in 5.24.0).
resource "cloudflare_ai_gateway" "this" {
  account_id = var.account_id
  id         = var.gateway_id

  authentication = var.authentication
  collect_logs   = var.collect_logs

  log_management          = var.log_storage.max_logs
  log_management_strategy = var.log_storage.when_full

  cache_ttl                  = local.cache_ttl
  cache_invalidate_on_update = local.cache_invalidate_on_update

  rate_limiting_limit     = local.rate_limiting_limit
  rate_limiting_interval  = local.rate_limiting_interval
  rate_limiting_technique = local.rate_limiting_technique

  retry_max_attempts = try(var.retries.max_attempts, null)
  retry_delay        = try(var.retries.delay_ms, null)
  retry_backoff      = try(var.retries.backoff, null)

  zdr                = var.zero_data_retention
  logpush            = var.logpush_public_key != null
  logpush_public_key = var.logpush_public_key
  store_id           = local.store_id

  # CREATE DOES NOT TAKE THESE. Cloudflare's published schema has dlp,
  # guardrails and spend_limits on its update call only, and provider 5.23
  # sends them on create regardless. If the API drops them, the new gateway
  # comes up without them: DLP and guardrails are still recorded as applied,
  # while spend limits may instead fail the apply as an inconsistent result.
  # Either way the refresh on the next plan shows what is really there, and
  # the apply after that turns them on. Plan again after creating a gateway
  # that declares any of the three, and apply what it shows, before pointing
  # a client at it.
  dlp          = local.dlp
  guardrails   = local.guardrails
  spend_limits = local.spend_limits

  lifecycle {
    precondition {
      condition     = var.authentication || length(local.needs_authentication) == 0
      error_message = "Gateway \"${var.gateway_id}\" sets ${join(", ", local.needs_authentication)} with authentication = false. Cloudflare only offers dynamic routing, BYOK and Zero Data Retention on an authenticated gateway. Turn authentication on - callers then need a token with AI Gateway Run - or drop them."
    }

    precondition {
      condition     = var.logpush_public_key == null || var.collect_logs
      error_message = "Gateway \"${var.gateway_id}\" sets logpush_public_key with collect_logs = false. Logpush exports the gateway's stored logs, so with logging off it has nothing to send. Turn collect_logs on, or drop the key."
    }
  }
}

# A route's elements cannot be changed in place. The API takes new elements
# as a new version plus a deployment of it, and provider 5.23's update only
# ever sends the route's name - so an edited element list would apply
# "successfully", change nothing, and show the same diff on every plan after.
# Instead, any change to a route's elements replaces the route, through this
# hash: the old route is deleted and a new one created under the same name.
#
# Clients address a route by name, as "dynamic/<name>", so they need no
# change - but requests to that route fail for the seconds between the delete
# and the create, and its version history goes with the old route. Schedule an
# element change on a live route.
resource "terraform_data" "route_revision" {
  for_each = local.routes

  input = sha256(jsonencode(each.value.elements))
}

resource "cloudflare_ai_gateway_dynamic_routing" "this" {
  for_each = local.routes

  account_id = var.account_id
  gateway_id = cloudflare_ai_gateway.this.id
  name       = each.key
  elements   = each.value.elements

  lifecycle {
    replace_triggered_by = [terraform_data.route_revision[each.key]]

    precondition {
      condition     = length(local.route_problems[each.key]) == 0
      error_message = "Route \"${each.key}\" on gateway \"${var.gateway_id}\" is not a valid routing graph: ${join("; ", local.route_problems[each.key])}."
    }
  }
}
