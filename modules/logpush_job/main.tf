# One Logpush job: one dataset, from one account or one zone, to one
# destination. Cloudflare batches the dataset's events and writes them out as
# they are produced, so once a job runs the destination - not Cloudflare - is
# where those logs live.
resource "cloudflare_logpush_job" "this" {
  account_id = var.account_id
  zone_id    = var.zone_id

  name    = var.name == null ? null : trimspace(var.name)
  dataset = var.dataset
  kind    = var.kind
  enabled = var.enabled
  filter  = local.filter

  # Sensitive in the provider schema as well as here, so neither is printed in a
  # plan, and neither is in any output.
  destination_conf    = trimspace(var.destination_conf)
  ownership_challenge = var.ownership_challenge

  max_upload_bytes            = var.max_upload_bytes
  max_upload_interval_seconds = var.max_upload_interval_seconds
  max_upload_records          = var.max_upload_records

  # frequency and logpull_options are deprecated in favour of max_upload_* and
  # output_options, and deliberately not exposed.
  output_options = var.output_options

  lifecycle {
    precondition {
      condition     = (var.account_id == null) != (var.zone_id == null)
      error_message = "Give exactly one of account_id and zone_id. The dataset (\"${var.dataset}\") decides which: http_requests and the other zone datasets need a zone_id, audit_logs, gateway_* and the other account datasets an account_id."
    }

    precondition {
      condition     = var.kind != "edge" || (var.dataset == "http_requests" && var.zone_id != null)
      error_message = "kind = \"edge\" is Edge Log Delivery, which Cloudflare offers for the zone-scoped http_requests dataset only. This job pushes \"${var.dataset}\" from ${local.scope == "zone" ? "a zone" : "an account"}."
    }

    precondition {
      condition     = try(var.output_options.merge_subrequests, null) != true || var.dataset == "http_requests"
      error_message = "output_options.merge_subrequests folds subrequests into their parent request, which only http_requests has. This job pushes \"${var.dataset}\"."
    }
  }
}
