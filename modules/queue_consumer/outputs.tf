output "consumer_id" {
  value       = cloudflare_queue_consumer.this.consumer_id
  description = "Identifier of the consumer. A queue takes one, so this is also what a second attachment made outside this module would collide with."
}

output "queue_id" {
  value       = cloudflare_queue_consumer.this.queue_id
  description = "Queue the consumer is attached to."
}

output "type" {
  value       = var.type
  description = "\"worker\" for push delivery into a Worker's queue() handler, or \"http_pull\" for a consumer that pulls batches over HTTP."
}

output "script_name" {
  value       = cloudflare_queue_consumer.this.script_name
  description = "Worker receiving batches from the queue, or null for a pull consumer."
}

output "dead_letter_queue" {
  value       = var.dead_letter_queue
  description = "Queue that receives a message once it has failed max_retries times. Null means a message that keeps failing is dropped, with nothing recording that it existed."
}
