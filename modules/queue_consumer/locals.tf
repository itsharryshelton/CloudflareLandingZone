# Derives the values main.tf's preconditions assert on. The settings object is
# passed to the provider as written: the variable already uses the provider's
# own attribute names.

locals {
  pull_only_settings_on_push_consumer = (
    var.type == "worker"
    ? compact([var.settings.visibility_timeout_ms == null ? "" : "visibility_timeout_ms"])
    : []
  )

  push_only_settings_on_pull_consumer = (
    var.type == "http_pull"
    ? compact([
      var.settings.max_concurrency == null ? "" : "max_concurrency",
      var.settings.max_wait_time_ms == null ? "" : "max_wait_time_ms",
    ])
    : []
  )
}
