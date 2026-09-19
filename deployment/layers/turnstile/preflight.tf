resource "terraform_data" "preflight" {
  input = {
    turnstile_widgets = length(var.turnstile_widgets)
    # Surfaced in the plan because it is the field whose change is an outage:
    # a mode or hostname edit is in-place, a region edit is a replacement.
    widget_regions = { for key, widget in local.widgets : key => widget.region }
  }

  lifecycle {
    precondition {
      condition     = var.allow_offlabel_widgets || length(local.offlabel_widgets) == 0
      error_message = "These widgets set offlabel = true, which removes Cloudflare branding: ${join(", ", local.offlabel_widgets)}. That is an Enterprise entitlement and a decision about what the page tells the visitor, so it is gated. Set allow_offlabel_widgets = true in layers/turnstile/defaults.auto.tfvars on a pull request that says why, or drop the flag."
    }

    # Cloudflare's own condition for the mode, not this repository's.
    precondition {
      condition     = var.invisible_mode_privacy_addendum_accepted || length(local.invisible_widgets) == 0
      error_message = "These widgets use invisible mode: ${join(", ", local.invisible_widgets)}. Nothing on the page tells the visitor a challenge ran, which is why Cloudflare requires its privacy addendum before the mode is used. Accept it and set invisible_mode_privacy_addendum_accepted = true in layers/turnstile/defaults.auto.tfvars, or use managed or non-interactive."
    }
  }
}
