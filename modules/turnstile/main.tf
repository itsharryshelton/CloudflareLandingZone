# Cloudflare Turnstile widgets for one account.
#
# A widget is a sitekey/secret pair plus the hostnames it may run on. It is
# account-scoped and not attached to a zone.
#
# WHAT TERRAFORM CANNOT DO HERE
# It creates the widget and holds the keys. It cannot put the sitekey into the
# page or the secret into the backend.
#
# `secret` is stored in state in plain text, because Terraform records what the
# API returned. Anyone with this layer's state can forge a valid /siteverify
# result. Rotating it means recreating the widget, which also changes the
# sitekey - so treat the state as the secret it holds.
resource "cloudflare_turnstile_widget" "this" {
  for_each = local.widgets

  account_id = var.account_id
  name       = each.value.name
  domains    = each.value.domains
  mode       = each.value.mode

  bot_fight_mode  = each.value.bot_fight_mode
  clearance_level = each.value.clearance_level
  ephemeral_id    = each.value.ephemeral_id
  offlabel        = each.value.offlabel
  region          = each.value.region

  lifecycle {
    precondition {
      condition     = length(local.duplicate_names) == 0
      error_message = "Two widgets share a name: ${join("; ", local.duplicate_names)}. Cloudflare allows it; this module does not, because the dashboard shows the name and not what embeds the sitekey, so the pair cannot be told apart when one of them breaks."
    }

    precondition {
      condition     = length(local.over_limit) == 0
      error_message = "These widgets list more hostnames than max_domains_per_widget (${var.max_domains_per_widget}): ${join("; ", local.over_limit)}. Cloudflare rejects the widget at apply, after the plan was approved. Remember a hostname already covers its subdomains, so the list is usually shorter than it first looks."
    }

    precondition {
      condition     = length(local.redundant_subdomains) == 0
      error_message = "These hostnames are already covered by another entry in the same widget: ${join("; ", local.redundant_subdomains)}. A hostname serves itself and all of its subdomains. Remove the subdomain entry, or the apex if the intent was to scope the widget to that subdomain only."
    }

    precondition {
      condition     = length(local.overlapping_domains) == 0
      error_message = "These hostnames are claimed by more than one widget: ${join("; ", local.overlapping_domains)}. Both widgets will work on the hostname, so which one a page is actually protected by depends on the sitekey somebody pasted into it - and that is not visible from here. Split the hostnames, or merge the widgets."
    }
  }
}
