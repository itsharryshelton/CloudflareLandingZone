variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. Queues and their consumers are account-scoped."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "queue_id" {
  type        = string
  description = <<-EOT
    Queue to attach the consumer to, typically module.queues[<key>].queue_id.

    Pass the queue module's output rather than a literal wherever the queue is
    declared in the same layer: the reference is what makes Terraform create the
    queue before attaching anything to it.
  EOT

  validation {
    condition     = trimspace(var.queue_id) != ""
    error_message = "queue_id must not be empty."
  }
}

variable "queue_name" {
  type        = string
  description = "Name of the queue being consumed. Not sent to Cloudflare - the consumer is attached by queue_id - but compared against dead_letter_queue, so a queue cannot be made its own dead letter queue."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.queue_name))
    error_message = "queue_name must be 1-63 characters of letters, numbers and hyphens, beginning with a letter or a number."
  }
}

variable "type" {
  type        = string
  default     = "worker"
  nullable    = false
  description = "\"worker\" for push delivery into a Worker's queue() handler, or \"http_pull\" for a consumer that pulls batches over HTTP on its own schedule."

  validation {
    condition     = contains(["worker", "http_pull"], var.type)
    error_message = "type must be \"worker\" or \"http_pull\"."
  }
}

variable "script_name" {
  type        = string
  default     = null
  description = <<-EOT
    The consuming Worker, for type "worker". Cloudflare rejects a consumer naming
    a Worker that does not exist yet, so a layer passes the name of the deployed
    Worker (module.worker_scripts[<key>].script_name) rather than the string from
    a variable file - that reference is what orders the two.

    A queue has exactly one consumer. One Worker can consume several queues, and
    any number of Workers can produce to one, but two consumers on a single queue
    is not something Cloudflare offers.
  EOT

  validation {
    condition     = var.script_name == null || can(regex("^[a-z0-9][a-z0-9_-]{0,62}$", coalesce(var.script_name, "-")))
    error_message = "script_name must be a valid Worker name: 1-63 characters of lowercase letters, numbers, hyphens or underscores."
  }
}

variable "dead_letter_queue" {
  type        = string
  default     = null
  description = "Name of another queue that receives a message once it has failed max_retries times. Without one, a message that keeps failing is dropped and nothing records it."

  validation {
    condition     = var.dead_letter_queue == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", coalesce(var.dead_letter_queue, "-")))
    error_message = "dead_letter_queue must be a valid queue name: 1-63 characters of letters, numbers and hyphens."
  }
}

variable "settings" {
  type = object({
    batch_size            = optional(number)
    max_concurrency       = optional(number)
    max_retries           = optional(number)
    max_wait_time_ms      = optional(number)
    retry_delay           = optional(number)
    visibility_timeout_ms = optional(number)
  })
  default     = {}
  nullable    = false
  description = <<-EOT
    Delivery tuning. Anything left null is Cloudflare's default.

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
    condition = (
      var.settings.batch_size == null ||
      (coalesce(var.settings.batch_size, 1) >= 1 && coalesce(var.settings.batch_size, 1) <= 100)
    )
    error_message = "settings.batch_size must be between 1 and 100 messages."
  }

  validation {
    condition = (
      var.settings.max_concurrency == null ||
      (coalesce(var.settings.max_concurrency, 1) >= 1 && coalesce(var.settings.max_concurrency, 1) <= 250)
    )
    error_message = "settings.max_concurrency must be between 1 and 250 concurrent invocations."
  }

  validation {
    condition = (
      var.settings.max_retries == null ||
      (coalesce(var.settings.max_retries, 0) >= 0 && coalesce(var.settings.max_retries, 0) <= 100)
    )
    error_message = "settings.max_retries must be between 0 and 100 delivery attempts."
  }

  validation {
    condition = (
      var.settings.max_wait_time_ms == null ||
      (coalesce(var.settings.max_wait_time_ms, 0) >= 0 && coalesce(var.settings.max_wait_time_ms, 0) <= 60000)
    )
    error_message = "settings.max_wait_time_ms must be between 0 and 60000 milliseconds (60 seconds)."
  }

  validation {
    condition = (
      var.settings.retry_delay == null ||
      (coalesce(var.settings.retry_delay, 0) >= 0 && coalesce(var.settings.retry_delay, 0) <= 86400)
    )
    error_message = "settings.retry_delay must be between 0 and 86400 seconds (24 hours)."
  }

  validation {
    condition = (
      var.settings.visibility_timeout_ms == null ||
      (coalesce(var.settings.visibility_timeout_ms, 1) >= 1 && coalesce(var.settings.visibility_timeout_ms, 1) <= 43200000)
    )
    error_message = "settings.visibility_timeout_ms must be between 1 and 43200000 milliseconds (12 hours)."
  }
}
