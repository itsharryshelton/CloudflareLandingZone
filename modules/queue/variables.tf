variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. Queues are account-scoped, and any Worker in the account that binds one can write to it."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "queue_name" {
  type        = string
  description = <<-EOT
    Queue name. Unique within the account, and the string a producer binding and
    another queue's dead letter setting both refer to it by.

    Cloudflare identifies a queue by ID, but the name is its identity everywhere
    a human writes it down, and changing it replaces the queue - taking any
    backlog with it. Include the environment: two deployments sharing a queue
    name is two sets of consumers competing for the same messages.
  EOT

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.queue_name))
    error_message = "queue_name must be 1-63 characters of letters, numbers and hyphens, beginning with a letter or a number."
  }
}

variable "settings" {
  type = object({
    delivery_delay           = optional(number)
    delivery_paused          = optional(bool, false)
    message_retention_period = optional(number)
  })
  default     = {}
  description = <<-EOT
    Queue-wide delivery behaviour.

      - delivery_delay          : seconds a message waits before a consumer may
                                  see it, applied to everything written to the
                                  queue. Null leaves it at Cloudflare's zero. A
                                  producer can delay an individual message
                                  instead, where the wait is a property of the
                                  message rather than of the queue.
      - delivery_paused         : stops delivery while producers carry on
                                  writing. Declared either way rather than only
                                  when true, so a queue somebody paused in the
                                  dashboard during an incident is un-paused by
                                  the next apply instead of quietly accumulating
                                  a backlog nobody is watching.
      - message_retention_period: seconds an unconsumed message is kept before it
                                  is dropped, 60 to 1209600 (14 days). Null
                                  leaves Cloudflare's default of four days.

    Retention is the only thing between a broken consumer and lost messages:
    nothing is delivered after it expires, and nothing reports what went.
  EOT

  validation {
    condition = (
      var.settings.delivery_delay == null ||
      (coalesce(var.settings.delivery_delay, 0) >= 0 && coalesce(var.settings.delivery_delay, 0) <= 86400)
    )
    error_message = "settings.delivery_delay must be between 0 and 86400 seconds (24 hours)."
  }

  validation {
    condition = (
      var.settings.message_retention_period == null ||
      (coalesce(var.settings.message_retention_period, 60) >= 60 && coalesce(var.settings.message_retention_period, 60) <= 1209600)
    )
    error_message = "settings.message_retention_period must be between 60 and 1209600 seconds (14 days)."
  }
}

variable "consumer" {
  type = object({
    type              = optional(string, "worker")
    script_name       = optional(string)
    dead_letter_queue = optional(string)

    settings = optional(object({
      batch_size            = optional(number)
      max_concurrency       = optional(number)
      max_retries           = optional(number)
      max_wait_time_ms      = optional(number)
      retry_delay           = optional(number)
      visibility_timeout_ms = optional(number)
    }), {})
  })
  default     = null
  description = <<-EOT
    What reads the queue. Null declares a queue with no consumer at all, which
    accepts messages and delivers none of them until retention expires - or one
    whose consumer is attached by the queue_consumer module, which is required
    wherever the consuming Worker is deployed by the same layer (see main.tf).

    A queue has exactly one consumer. One Worker can consume several queues, and
    any number of Workers can produce to one, but two consumers on a single queue
    is not something Cloudflare offers - a single reader is what makes
    at-least-once delivery possible without two handlers racing for the same
    message.

      - type             : "worker" for push delivery into a Worker's queue()
                           handler, or "http_pull" for a consumer that pulls
                           batches over HTTP on its own schedule.
      - script_name      : the consuming Worker, for type "worker". Cloudflare
                           rejects a consumer naming a Worker that does not exist
                           yet, so it must already be deployed - by another
                           layer or pipeline.
      - dead_letter_queue: name of another queue that receives a message once it
                           has failed max_retries times. Without one, a message
                           that keeps failing is dropped and nothing records it.
      - settings         : delivery tuning, below.

    CONSUMER SETTINGS
      - batch_size           : messages delivered at once, 1-100. Default 10.
      - max_wait_time_ms     : how long Cloudflare waits for a batch to fill
                               before delivering a partial one, 0-60000. Push
                               consumers only.
      - max_concurrency      : how many consumer invocations may run at once,
                               1-250. Push consumers only. Left null, Cloudflare
                               scales it against the backlog, which is usually
                               right; cap it where the consumer calls something
                               that cannot take the parallelism.
      - max_retries          : delivery attempts before a message is dead
                               lettered or dropped, 0-100. Default 3.
      - retry_delay          : seconds before a failed message is redelivered,
                               0-86400. Retrying immediately against a failing
                               dependency is only a faster way to exhaust the
                               retries.
      - visibility_timeout_ms: how long a pulled batch is leased before it
                               becomes visible to another pull, up to 43200000
                               (12 hours). Pull consumers only.

    A consumer is handed a batch and either acknowledges it or does not, so a
    handler that throws puts the whole batch back - including the messages it had
    already processed. Acknowledge message by message in the Worker wherever
    partial failure is normal.
  EOT

  validation {
    condition     = var.consumer == null || contains(["worker", "http_pull"], try(var.consumer.type, "worker"))
    error_message = "consumer.type must be \"worker\" or \"http_pull\"."
  }

  validation {
    condition = (
      var.consumer == null || try(var.consumer.script_name, null) == null ||
      can(regex("^[a-z0-9][a-z0-9_-]{0,62}$", try(var.consumer.script_name, "")))
    )
    error_message = "consumer.script_name must be a valid Worker name: 1-63 characters of lowercase letters, numbers, hyphens or underscores."
  }

  validation {
    condition = (
      var.consumer == null || try(var.consumer.dead_letter_queue, null) == null ||
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", try(var.consumer.dead_letter_queue, "")))
    )
    error_message = "consumer.dead_letter_queue must be a valid queue name: 1-63 characters of letters, numbers and hyphens."
  }

  validation {
    condition = (
      var.consumer == null || try(var.consumer.settings.batch_size, null) == null ||
      (try(var.consumer.settings.batch_size, 1) >= 1 && try(var.consumer.settings.batch_size, 1) <= 100)
    )
    error_message = "consumer.settings.batch_size must be between 1 and 100 messages."
  }

  validation {
    condition = (
      var.consumer == null || try(var.consumer.settings.max_concurrency, null) == null ||
      (try(var.consumer.settings.max_concurrency, 1) >= 1 && try(var.consumer.settings.max_concurrency, 1) <= 250)
    )
    error_message = "consumer.settings.max_concurrency must be between 1 and 250 concurrent invocations."
  }

  validation {
    condition = (
      var.consumer == null || try(var.consumer.settings.max_retries, null) == null ||
      (try(var.consumer.settings.max_retries, 0) >= 0 && try(var.consumer.settings.max_retries, 0) <= 100)
    )
    error_message = "consumer.settings.max_retries must be between 0 and 100 delivery attempts."
  }

  validation {
    condition = (
      var.consumer == null || try(var.consumer.settings.max_wait_time_ms, null) == null ||
      (try(var.consumer.settings.max_wait_time_ms, 0) >= 0 && try(var.consumer.settings.max_wait_time_ms, 0) <= 60000)
    )
    error_message = "consumer.settings.max_wait_time_ms must be between 0 and 60000 milliseconds (60 seconds)."
  }

  validation {
    condition = (
      var.consumer == null || try(var.consumer.settings.retry_delay, null) == null ||
      (try(var.consumer.settings.retry_delay, 0) >= 0 && try(var.consumer.settings.retry_delay, 0) <= 86400)
    )
    error_message = "consumer.settings.retry_delay must be between 0 and 86400 seconds (24 hours)."
  }

  validation {
    condition = (
      var.consumer == null || try(var.consumer.settings.visibility_timeout_ms, null) == null ||
      (try(var.consumer.settings.visibility_timeout_ms, 1) >= 1 && try(var.consumer.settings.visibility_timeout_ms, 1) <= 43200000)
    )
    error_message = "consumer.settings.visibility_timeout_ms must be between 1 and 43200000 milliseconds (12 hours)."
  }
}
