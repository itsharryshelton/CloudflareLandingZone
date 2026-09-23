output "ai_gateway_endpoints" {
  description = <<-EOT
    The hand-over: per gateway, the base URLs an application is pointed at, and
    whether it must authenticate. Nothing in this repository changes an
    application's configuration, so a gateway that appears here and in no
    application's base URL is proxying nothing.

    - `base`           - <base>/<provider>/<that provider's API path>
    - `openai_compat`  - OpenAI SDK base URL; model "<provider>/<model>" or
                         "dynamic/<route>"
    - `authentication` - true means every request needs
                         `cf-aig-authorization: Bearer <token>`, with a token
                         carrying AI Gateway Run. This layer does not create it.
  EOT
  value = {
    for key, gateway in module.ai_gateway : key => merge(gateway.endpoints, {
      authentication = gateway.gateway.authentication
    })
  }
}

output "ai_gateway_routes" {
  description = "Per gateway, route name => the model string a client sends (\"dynamic/<name>\"), the route's ID and its deployed version. The ID changes whenever the route's elements do, because that replaces the route; the model string does not."
  value       = { for key, gateway in module.ai_gateway : key => gateway.routes }
}

output "ai_gateways" {
  description = "Per gateway identity and posture: ID, authentication, log collection, Logpush and creation time."
  value       = { for key, gateway in module.ai_gateway : key => gateway.gateway }
}
