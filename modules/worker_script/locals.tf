# Turns the operator-facing schema into the shapes the Workers API wants, and
# derives the values main.tf's preconditions assert on.
#
# The binding list is passed through unchanged: the variable already uses the
# provider's own attribute names, so a rename here would only add a translation
# table to keep in step with Cloudflare's. The mapping that does happen is the
# flat `observability` object, which the API nests, and the collection keys.

locals {
  bindings = var.bindings

  # `logs` is only sent when observability is on. Cloudflare accepts a logs block
  # under a disabled parent and shows it in the dashboard, which reads as though
  # something is being recorded when nothing is.
  observability = {
    enabled            = var.observability.enabled
    head_sampling_rate = var.observability.head_sampling_rate
    logs = var.observability.enabled ? {
      enabled         = var.observability.logs_enabled
      invocation_logs = var.observability.invocation_logs
    } : null
  }

  placement = var.placement_mode == null ? null : { mode = var.placement_mode }

  # Keyed by pattern and hostname rather than by list position, so reordering a
  # list never proposes destroying and recreating a live route.
  routes         = { for route in var.routes : lower(route.pattern) => route }
  custom_domains = { for domain in var.custom_domains : lower(domain.hostname) => domain }

  cron_schedules = [for schedule in var.cron_schedules : { cron = schedule }]

  # Guardrail inputs
  source_declared = length(compact([
    var.content == null ? "" : "content",
    var.content_file == null ? "" : "content_file",
  ]))

  syntax_declared = length(compact([
    var.main_module == null ? "" : "main_module",
    var.body_part == null ? "" : "body_part",
  ]))

  # The host half of each route pattern, for comparison against the custom
  # domains. Cloudflare treats a custom domain as owning its hostname outright,
  # so a route on the same host is a configuration that cannot do what it looks
  # like it does.
  route_hosts = { for route in var.routes : lower(route.pattern) => lower(split("/", route.pattern)[0]) }

  hostnames_claimed_twice = [
    for pattern, host in local.route_hosts : "\"${pattern}\" and custom domain \"${host}\""
    if contains(keys(local.custom_domains), host)
  ]

  # A binding that names a secret inline. Reported by the module rather than
  # rejected, because there are legitimate uses; the calling layer is where the
  # policy decision lives.
  inline_secret_bindings = [for binding in var.bindings : binding.name if binding.type == "secret_text"]
}
