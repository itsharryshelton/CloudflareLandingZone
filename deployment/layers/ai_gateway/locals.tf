locals {
  # Layer defaults resolved here rather than in the module, so the module stays
  # a plain mapping onto the provider and the platform baseline lives in one
  # file the operator can read (defaults.auto.tfvars).
  gateways = {
    for key, gateway in var.ai_gateways : key => merge(gateway, {
      authentication = coalesce(gateway.authentication, var.default_authentication)
      collect_logs   = coalesce(gateway.collect_logs, var.default_collect_logs)
      log_storage = {
        max_logs  = coalesce(gateway.log_storage.max_logs, var.default_log_storage.max_logs)
        when_full = coalesce(gateway.log_storage.when_full, var.default_log_storage.when_full)
      }
    })
  }

  # Derived assertions, consumed by preflight.tf. Rules about one gateway -
  # its routing graphs, what needs authentication - are the module's, so they
  # hold for any consumer of it. What is left here is across gateways, or this
  # platform's policy, which a different deployment may set differently.

  duplicate_gateway_ids = sort([
    for id, claimants in {
      for key, gateway in local.gateways : gateway.gateway_id => key...
    } : "\"${id}\" (${join(", ", sort(claimants))})" if length(claimants) > 1
  ])

  unauthenticated_gateways = sort([
    for key, gateway in local.gateways : key if !gateway.authentication
  ])
}
