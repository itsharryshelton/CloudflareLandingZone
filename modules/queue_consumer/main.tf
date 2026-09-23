# The single consumer that reads one Cloudflare queue. Normalisation lives in
# locals.tf.
#
# This is its own module rather than part of `queue` because of how Terraform
# orders module calls. A reference such as `module.queues[each.key].queue_name`
# has a key only known at evaluation, so Terraform records it as a dependency on
# the whole module call - every output and every resource inside it - not on the
# one output. A layer that binds a Worker to a queue and names the same Worker as
# a queue's consumer would then have the Worker waiting on the queue module and
# the queue module waiting on the Worker: a cycle, reported at validate.
#
# Kept apart, the ordering is a straight line: queue, then the Worker that
# produces to it or consumes it, then this consumer.

resource "cloudflare_queue_consumer" "this" {
  account_id = var.account_id
  queue_id   = var.queue_id

  type              = var.type
  script_name       = var.script_name
  dead_letter_queue = var.dead_letter_queue
  settings          = var.settings

  lifecycle {
    precondition {
      condition     = var.type != "worker" || var.script_name != null
      error_message = "A consumer of type \"worker\" needs script_name - the Worker whose queue() handler receives each batch. For a consumer that pulls batches over HTTP instead, set type = \"http_pull\"."
    }

    precondition {
      condition     = var.type != "http_pull" || var.script_name == null
      error_message = "script_name is set on a consumer of type \"http_pull\". A pull consumer is not a Worker - it is whatever holds the credentials to call the pull endpoint - so the name would be silently ignored."
    }

    precondition {
      condition     = var.dead_letter_queue == null || var.dead_letter_queue != var.queue_name
      error_message = "This queue is its own dead letter queue (\"${var.queue_name}\"). A message that exhausts its retries would be written straight back to the queue it just failed on, which is a loop that bills for every attempt and never drains. Point it at a separate queue."
    }

    precondition {
      condition     = length(local.pull_only_settings_on_push_consumer) == 0
      error_message = "These settings only apply to a pull consumer and are set on a push consumer: ${join(", ", local.pull_only_settings_on_push_consumer)}. Cloudflare accepts them and ignores them, so the variable file reads as though a lease timeout is in force when nothing is leasing anything."
    }

    precondition {
      condition     = length(local.push_only_settings_on_pull_consumer) == 0
      error_message = "These settings only apply to a push consumer and are set on a pull consumer: ${join(", ", local.push_only_settings_on_pull_consumer)}. A pull consumer decides its own batch size and concurrency when it calls the pull endpoint, so Cloudflare has nothing to apply them to."
    }
  }
}
