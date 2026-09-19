locals {
  # Layer defaults resolved here rather than in the module, so the module stays a
  # plain mapping onto the provider and the platform baseline lives in one file
  # the operator can read (defaults.auto.tfvars).
  widgets = {
    for key, widget in var.turnstile_widgets : key => merge(widget, {
      mode   = coalesce(widget.mode, var.default_widget_mode)
      region = coalesce(widget.region, var.default_widget_region)
    })
  }

  # Derived assertions, consumed by preflight.tf. Cross-widget rules - duplicate
  # names, overlapping hostnames, the hostname ceiling - are the module's, so
  # they hold for any consumer of it. What is left here is this platform's
  # policy, which a different deployment may set differently.

  offlabel_widgets = sort([
    for key, widget in local.widgets : key if widget.offlabel
  ])

  invisible_widgets = sort([
    for key, widget in local.widgets : key if widget.mode == "invisible"
  ])
}
