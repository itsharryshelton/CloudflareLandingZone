# One Cloudflare queue and, where one is declared, the single consumer that
# reads it. Normalisation lives in locals.tf.
#
# Producers are deliberately not modelled here. A Worker writes to a queue
# through a `queue` binding on the Worker itself, so the producer side is
# configuration of the producing Worker rather than of the queue - which is also
# why a queue can be created, reviewed and applied before anything writes to it.
#
# The consumer is a separate resource from the queue for the same reason it is a
# separate API call: the queue has to exist before a consumer can be attached to
# it, and the consuming Worker has to exist before it can be named.
#
# Only use `consumer` here where the consuming Worker is deployed outside the
# calling layer. A layer that also deploys the Worker, and binds any Worker in
# the same module call to one of these queues, must use the queue_consumer
# module instead: Terraform orders a for_each module call as a whole, so a
# consumer in here waiting on the Worker makes the Worker wait on itself.

resource "cloudflare_queue" "this" {
  account_id = var.account_id
  queue_name = var.queue_name

  settings = local.settings
}

resource "cloudflare_queue_consumer" "this" {
  count = local.consumer_declared ? 1 : 0

  account_id = var.account_id

  # Referenced through the resource rather than through a variable, so Terraform
  # creates the queue first without being told to.
  queue_id = cloudflare_queue.this.queue_id

  type              = local.consumer_type
  script_name       = local.consumer_script_name
  dead_letter_queue = local.consumer_dead_letter_queue
  settings          = local.consumer_settings

  lifecycle {
    precondition {
      condition     = local.consumer_type != "worker" || local.consumer_script_name != null
      error_message = "A consumer of type \"worker\" needs script_name - the Worker whose queue() handler receives each batch. For a consumer that pulls batches over HTTP instead, set type = \"http_pull\"."
    }

    precondition {
      condition     = local.consumer_type != "http_pull" || local.consumer_script_name == null
      error_message = "consumer.script_name is set on a consumer of type \"http_pull\". A pull consumer is not a Worker - it is whatever holds the credentials to call the pull endpoint - so the name would be silently ignored."
    }

    precondition {
      condition     = local.consumer_dead_letter_queue == null || local.consumer_dead_letter_queue != var.queue_name
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
