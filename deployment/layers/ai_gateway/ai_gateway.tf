# Cloudflare AI Gateway: gateways and their dynamic routes.
#
# Its own layer, not part of workers, because a gateway is not compute and is
# attached to no zone. It is a proxy in front of AI providers, reached by URL,
# with its own permission group - and the token that can rewrite its DLP,
# guardrails and spend limits should not also be able to change the Workers
# that call it. It reads nothing and nothing reads it.
#
# What makes a gateway useful is outside this layer: the application's base
# URL, the Run token its callers authenticate with, and any BYOK provider keys
# in Secrets Store. See outputs.tf for the endpoints to hand over, and
# imports.tf before a first apply against an account already using AI Gateway.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/yourorg/CloudflareLandingZone//modules/ai_gateway?ref=v1.0.0"
module "ai_gateway" {
  source = "../../../modules/ai_gateway"

  for_each = local.gateways

  account_id = var.cloudflare_account_id
  gateway_id = each.value.gateway_id

  authentication = each.value.authentication
  collect_logs   = each.value.collect_logs
  log_storage    = each.value.log_storage

  cache      = each.value.cache
  rate_limit = each.value.rate_limit
  retries    = each.value.retries

  zero_data_retention = each.value.zero_data_retention
  logpush_public_key  = each.value.logpush_public_key
  secrets_store_id    = each.value.secrets_store_id

  dlp_policies = each.value.dlp_policies
  guardrails   = each.value.guardrails
  spend_limits = each.value.spend_limits

  routes = each.value.routes
}
