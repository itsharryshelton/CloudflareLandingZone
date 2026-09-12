# Turns the operator-facing schema into the shapes the Queues API wants, and
# derives the values main.tf's preconditions assert on.
#
# The settings objects are passed through field for field rather than renamed:
# the variable already uses the provider's own attribute names, so a translation
# table here would only be one more thing to keep in step with Cloudflare's.

locals {
  # Sent whole, including delivery_paused, so the dashboard's pause switch is
  # something a plan can see. A queue paused by hand and forgotten is a backlog
  # that expires quietly, which is the failure this module exists to make loud.
  settings = {
    delivery_delay           = var.settings.delivery_delay
    delivery_paused          = var.settings.delivery_paused
    message_retention_period = var.settings.message_retention_period
  }

  consumer_declared = var.consumer != null
  consumer_type     = try(var.consumer.type, "worker")

  consumer_script_name       = try(var.consumer.script_name, null)
  consumer_dead_letter_queue = try(var.consumer.dead_letter_queue, null)
  consumer_settings          = try(var.consumer.settings, null)

  # Guardrail inputs
  pull_only_settings_on_push_consumer = (
    local.consumer_declared && local.consumer_type == "worker"
    ? compact([try(local.consumer_settings.visibility_timeout_ms, null) == null ? "" : "visibility_timeout_ms"])
    : []
  )

  push_only_settings_on_pull_consumer = (
    local.consumer_declared && local.consumer_type == "http_pull"
    ? compact([
      try(local.consumer_settings.max_concurrency, null) == null ? "" : "max_concurrency",
      try(local.consumer_settings.max_wait_time_ms, null) == null ? "" : "max_wait_time_ms",
    ])
    : []
  )
}
