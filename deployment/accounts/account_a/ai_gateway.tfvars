# Account: account_a - Cloudflare AI Gateway. Consumed by the ai_gateway layer only.
#
#   terraform -chdir=layers/ai_gateway plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/ai_gateway.tfvars
#
# Gateways are account-scoped, not zone-scoped: nothing here has to match a key in
# zones.tfvars. An application uses a gateway only once its base URL is changed to
# the one in the ai_gateway_endpoints output - this file cannot do that part.
#
# The keys are state addresses; gateway_id is what clients call. Renaming a key
# without a `moved` block deletes and recreates the gateway, and its logs with it.

ai_gateways = {
  # A customer-facing assistant: authenticated (the platform default), logging on,
  # a short cache for repeated questions, and a gateway-wide ceiling on requests.
  support_assistant = {
    gateway_id = "support-assistant"

    cache      = { ttl = 300 }
    rate_limit = { limit = 600, interval = 60, technique = "sliding" }
    retries    = { max_attempts = 2, delay_ms = 500, backoff = "exponential" }

    # Prompt injection blocked outright; the rest only flagged into the log while
    # the false-positive rate is learned. Billed as Workers AI inference, and adds
    # about half a second to each request.
    guardrails = {
      prompt   = { prompt_injection = "BLOCK", hate = "FLAG", violent_crimes = "FLAG" }
      response = { hate = "FLAG" }
    }

    # DLP needs Zero Trust DLP profile UUIDs from this account - copy them from the
    # DLP section of the Zero Trust dashboard:
    #
    # dlp_policies = {
    #   block-financial-data = {
    #     action   = "BLOCK"
    #     check    = ["REQUEST", "RESPONSE"]
    #     profiles = ["<DLP profile UUID>"]
    #   }
    # }
    #
    # Spend limits: `limit` is US dollars, but Cloudflare does not document the unit
    # of `window`. Create one rule in the dashboard, read it back from the API and
    # copy its window value before relying on a number here:
    #
    # spend_limits = {
    #   per_user = { limit = 5, window = <verified value>, partition_by = ["user_id"] }
    # }

    # Clients send model "dynamic/support-default" to the OpenAI-compatible
    # endpoint. Cloudflare's docs expect the providers a route calls to have BYOK
    # keys stored on the gateway; those are added outside Terraform.
    routes = {
      support-default = {
        elements = {
          start = { type = "start", outputs = { next = "primary" } }
          primary = {
            type     = "model"
            provider = "openai"
            model    = "gpt-5-mini"
            retries  = 1
            timeout  = 30000
            outputs  = { success = "end", fallback = "budget" }
          }
          budget = {
            type     = "model"
            provider = "workers-ai"
            model    = "@cf/meta/llama-3.1-8b-instruct"
            retries  = 0
            timeout  = 30000
            outputs  = { success = "end" }
          }
          end = { type = "end" }
        }
      }
    }
  }

  # An internal tool fed customer records: nothing is logged at Cloudflare, so
  # there is no stored copy of the prompts to protect.
  internal_tools = {
    gateway_id   = "internal-tools"
    collect_logs = false
  }
}
