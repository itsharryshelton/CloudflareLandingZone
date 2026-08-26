# One Worker: the script itself, what it is allowed to reach, and everything that
# can invoke it - routes, custom domains and cron triggers. Normalisation lives in
# locals.tf.
#
# Cloudflare also ships beta `cloudflare_worker`, `cloudflare_worker_version` and
# `cloudflare_workers_deployment` resources, which model immutable versions and
# gradual rollout. They are the direction of travel and are worth revisiting once
# they leave beta; `cloudflare_workers_script` is used here because a landing zone
# should not pin a fleet to a beta resource whose state shape may still change.

resource "cloudflare_workers_script" "this" {
  account_id  = var.account_id
  script_name = var.script_name

  content        = var.content
  content_file   = var.content_file
  content_sha256 = var.content_sha256

  main_module = var.main_module
  body_part   = var.body_part

  compatibility_date  = var.compatibility_date
  compatibility_flags = var.compatibility_flags
  usage_model         = var.usage_model

  bindings      = local.bindings
  placement     = local.placement
  limits        = var.limits
  logpush       = var.logpush
  observability = local.observability

  tail_consumers = var.tail_consumers

  lifecycle {
    precondition {
      condition     = local.source_declared == 1
      error_message = "Set exactly one of content or content_file (currently ${local.source_declared}). Inline source is carried in state; a file is not, and is what a bundled Worker should use."
    }

    precondition {
      condition     = var.content_file == null || var.content_sha256 != null
      error_message = "content_file is set without content_sha256. The file is never read into state, so with no hash to compare, editing the Worker produces \"No changes\" and deploys nothing. Pass filesha256() of the same path."
    }

    precondition {
      condition     = var.content_sha256 == null || var.content_file != null
      error_message = "content_sha256 is set without content_file. It is only meaningful as the hash of a file Terraform is not otherwise reading."
    }

    precondition {
      condition     = local.syntax_declared == 1
      error_message = "Set exactly one of main_module or body_part (currently ${local.syntax_declared}). main_module means ES module syntax with bindings on `env`; body_part means the older service worker syntax with bindings as globals. Cloudflare cannot infer which the uploaded source is."
    }
  }
}

# Routes and custom domains are separate resources on purpose: removing a route
# from the list removes it from Cloudflare, rather than leaving a hostname
# pointing at a Worker nobody remembers deploying.
resource "cloudflare_workers_route" "this" {
  for_each = local.routes

  zone_id = each.value.zone_id
  pattern = each.value.pattern
  script  = cloudflare_workers_script.this.script_name

  lifecycle {
    precondition {
      condition     = length(local.hostnames_claimed_twice) == 0
      error_message = "A route and a custom domain claim the same hostname: ${join("; ", local.hostnames_claimed_twice)}. A custom domain owns its hostname outright, so the route is dead configuration that reads as though it is doing something."
    }
  }
}

resource "cloudflare_workers_custom_domain" "this" {
  for_each = local.custom_domains

  account_id = var.account_id
  service    = cloudflare_workers_script.this.script_name

  hostname  = each.key
  zone_id   = each.value.zone_id
  zone_name = each.value.zone_name
}

# One resource holds the whole schedule list, so removing an expression removes
# the trigger. Guarded rather than always-declared because an empty schedules list
# is not the same thing to Cloudflare as no cron configuration at all.
resource "cloudflare_workers_cron_trigger" "this" {
  count = length(local.cron_schedules) > 0 ? 1 : 0

  account_id  = var.account_id
  script_name = cloudflare_workers_script.this.script_name
  schedules   = local.cron_schedules
}
