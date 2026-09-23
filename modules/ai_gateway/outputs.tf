output "gateway" {
  description = "Gateway identity and the settings a caller has to know about. `authentication` true means every request to the gateway endpoint needs a `cf-aig-authorization` header carrying a token with AI Gateway Run; nothing here creates that token."
  value = {
    id             = cloudflare_ai_gateway.this.id
    authentication = cloudflare_ai_gateway.this.authentication
    collect_logs   = cloudflare_ai_gateway.this.collect_logs
    logpush        = cloudflare_ai_gateway.this.logpush
    created_at     = cloudflare_ai_gateway.this.created_at
  }
}

output "endpoints" {
  description = <<-EOT
    The base URLs a client is pointed at. Built from the account and gateway
    IDs, which is all they are; the API does not return them.

    - `base`          - Add the provider's path segment and then that provider's
                        own API path: <base>/openai/chat/completions. Posting to
                        the bare URL is the Universal Endpoint, which Cloudflare
                        has deprecated.
    - `openai_compat` - The OpenAI-compatible endpoint, as an OpenAI SDK base URL.
                        The model is "<provider>/<model>", or "dynamic/<route>"
                        for a dynamic route - the only endpoint that routes.
  EOT
  value = {
    base          = "https://gateway.ai.cloudflare.com/v1/${var.account_id}/${cloudflare_ai_gateway.this.id}"
    openai_compat = "https://gateway.ai.cloudflare.com/v1/${var.account_id}/${cloudflare_ai_gateway.this.id}/compat"
  }
}

output "routes" {
  description = "Route name => the model string a client sends to use it, the route's ID and its deployed version. The ID changes whenever the route's elements do, because that replaces the route; the model string does not."
  value = {
    for name, route in cloudflare_ai_gateway_dynamic_routing.this : name => {
      model      = "dynamic/${name}"
      id         = route.id
      version_id = route.deployment.version_id
    }
  }
}
