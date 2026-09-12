output "queue_id" {
  value       = cloudflare_queue.this.queue_id
  description = "Opaque queue identifier. This is what the Queues API and a pull consumer address the queue by; a Worker's queue binding uses the name instead."
}

output "queue_name" {
  value       = cloudflare_queue.this.queue_name
  description = "Queue name as Cloudflare holds it. This is what a producer binding points at, and what another queue names as its dead_letter_queue."
}

output "consumer_id" {
  value       = try(cloudflare_queue_consumer.this[0].consumer_id, null)
  description = "Identifier of the queue's consumer, or null where the queue has none. A queue with no consumer accepts messages and delivers none of them until retention expires."
}

output "consumer_script_name" {
  value       = try(cloudflare_queue_consumer.this[0].script_name, null)
  description = "Worker receiving batches from this queue, or null for a pull consumer or no consumer at all."
}

output "dead_letter_queue" {
  value       = local.consumer_dead_letter_queue
  description = "Queue that receives a message once it has failed max_retries times. Null means a message that keeps failing is dropped, with nothing recording that it existed."
}

output "delivery_paused" {
  value       = cloudflare_queue.this.settings.delivery_paused
  description = "Whether delivery to the consumer is stopped. True means producers are still writing and the backlog is growing towards the retention period."
}

output "producers_total_count" {
  value       = cloudflare_queue.this.producers_total_count
  description = "How many producers Cloudflare sees bound to this queue as of the last refresh, including Workers deployed outside this pipeline. Zero on a queue nothing writes to yet."
}

output "consumers_total_count" {
  value       = cloudflare_queue.this.consumers_total_count
  description = "How many consumers Cloudflare sees on this queue as of the last refresh. A queue takes one, so anything other than 0 or 1 means something outside this module has attached itself."
}

output "created_on" {
  value       = cloudflare_queue.this.created_on
  description = "When the queue was created."
}

output "modified_on" {
  value       = cloudflare_queue.this.modified_on
  description = "When the queue was last modified, by anything - including a dashboard change this configuration will overwrite on the next apply."
}
