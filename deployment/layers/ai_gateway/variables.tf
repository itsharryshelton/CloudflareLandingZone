# Layer ai_gateway - inputs.
#
# Cloudflare AI Gateway: the proxy an application sends its LLM traffic
# through, for logging, caching, rate limits, DLP, guardrails, spend limits and
# dynamic routing across providers. Account-scoped and attached to no zone, so
# this layer holds its own state and reads nothing else.
#
# It declares gateways and their routes. It does not change an application's
# base URL, create the token its callers authenticate with, or store the BYOK
# provider keys a gateway spends on.
#
# Config files:
#   accounts/<account>/account.tfvars    - the account ID, shared with every layer
#   accounts/<account>/ai_gateway.tfvars - the gateways, consumed only here

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID this layer run targets. Supplied from accounts/<account>/account.tfvars. A gateway is account-scoped, and its endpoint URL carries this ID."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "ai_gateways" {
  description = <<-EOT
    AI gateways, keyed by a logical key. The key is the state address and what
    the outputs are keyed by. Renaming one plans a delete and a create of the
    same gateway_id in no guaranteed order: the create is refused while the ID
    still exists, or it lands after the delete and the logs are gone. Rename a
    key with a `moved` block.

    - `gateway_id`          - The gateway's ID and the path segment in every
                              client's base URL. FIXED AT CREATION: a change
                              replaces the gateway, deletes its logs and routes,
                              and breaks every client using the old URL.
                              "default" is Cloudflare's auto-created gateway -
                              import it, see imports.tf.
    - `authentication`      - (Optional) Falls back to var.default_authentication.
                              false is gated by var.allow_unauthenticated_gateways.
    - `collect_logs`        - (Optional) Falls back to var.default_collect_logs.
                              Logs are full prompts and responses.
    - `log_storage`         - (Optional) max_logs (10000-10000000) and when_full
                              (DELETE_OLDEST | STOP_INSERTING). Each falls back to
                              var.default_log_storage.
    - `cache`               - (Optional) { ttl, invalidate_on_update }. Omit for off.
    - `rate_limit`          - (Optional) { limit, interval, technique }. Omit for off.
    - `retries`             - (Optional) { max_attempts, delay_ms, backoff }.
    - `zero_data_retention` - (Optional, default false) Unified Billing traffic to
                              OpenAI and Anthropic only. Not a logging switch.
    - `logpush_public_key`  - (Optional) RSA public key, PEM. Never the private one.
    - `secrets_store_id`    - (Optional) The Secrets Store holding BYOK keys.
    - `dlp_policies`        - (Optional) policy ID => { action, check, profiles, enabled }.
    - `guardrails`          - (Optional) { prompt, response }, category => FLAG | BLOCK.
    - `spend_limits`        - (Optional) rule ID => { limit (USD), window, ... }.
    - `routes`              - (Optional) route name => { elements }.

    Every field is described in full on the matching variable of
    modules/ai_gateway, which is where it is validated.

    A NEW GATEWAY MAY NEED TWO APPLIES
    Cloudflare's create call does not take dlp_policies, guardrails or
    spend_limits - only its update call does. Plan again after the apply that
    creates a gateway declaring any of them, and apply what that plan shows,
    before pointing a client at it.
  EOT

  type = map(object({
    gateway_id     = string
    authentication = optional(bool)
    collect_logs   = optional(bool)
    log_storage = optional(object({
      max_logs  = optional(number)
      when_full = optional(string)
    }), {})
    cache = optional(object({
      ttl                  = number
      invalidate_on_update = optional(bool, false)
    }))
    rate_limit = optional(object({
      limit     = number
      interval  = number
      technique = optional(string, "fixed")
    }))
    retries = optional(object({
      max_attempts = number
      delay_ms     = number
      backoff      = string
    }))
    zero_data_retention = optional(bool, false)
    logpush_public_key  = optional(string)
    secrets_store_id    = optional(string)
    dlp_policies = optional(map(object({
      action   = string
      check    = list(string)
      profiles = list(string)
      enabled  = optional(bool, true)
    })), {})
    guardrails = optional(object({
      prompt   = optional(map(string), {})
      response = optional(map(string), {})
    }))
    spend_limits = optional(map(object({
      limit            = number
      window           = number
      technique        = optional(string, "sliding")
      enabled          = optional(bool, true)
      models           = optional(list(string), [])
      providers        = optional(list(string), [])
      partition_by     = optional(list(string), [])
      metadata_filters = optional(map(list(string)), {})
    })), {})
    routes = optional(map(object({
      elements = map(object({
        type       = string
        outputs    = optional(map(string), {})
        conditions = optional(string)
        key        = optional(string)
        limit      = optional(number)
        limit_type = optional(string)
        window     = optional(number)
        provider   = optional(string)
        model      = optional(string)
        retries    = optional(number)
        timeout    = optional(number)
      }))
    })), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.ai_gateways) : can(regex("^[a-z0-9_]+$", key))])
    error_message = "ai_gateways keys must be lowercase alphanumeric with underscores. The key is a state address; the gateway's own ID is gateway_id."
  }
}

variable "default_authentication" {
  type        = bool
  description = "Authentication for a gateway that does not state it. Set in defaults.auto.tfvars."
}

variable "default_collect_logs" {
  type        = bool
  description = "Log collection for a gateway that does not state it. Set in defaults.auto.tfvars."
}

variable "default_log_storage" {
  type = object({
    max_logs  = number
    when_full = string
  })
  description = "Log storage cap and behaviour at the cap, for a gateway that does not state them. Set in defaults.auto.tfvars."

  validation {
    condition     = var.default_log_storage.max_logs >= 10000 && var.default_log_storage.max_logs <= 10000000
    error_message = "default_log_storage.max_logs must be from 10000 to 10000000."
  }

  validation {
    condition     = contains(["DELETE_OLDEST", "STOP_INSERTING"], var.default_log_storage.when_full)
    error_message = "default_log_storage.when_full must be DELETE_OLDEST or STOP_INSERTING."
  }
}

variable "max_ai_gateways" {
  type        = number
  description = "Ceiling on gateways in one account, enforced before the API sees them. Cloudflare's own is 10 on Workers Free and 20 on Workers Paid, and the gateway past it is refused at apply, after the plan was approved. Set in defaults.auto.tfvars."

  validation {
    condition     = var.max_ai_gateways >= 1 && floor(var.max_ai_gateways) == var.max_ai_gateways
    error_message = "max_ai_gateways must be a whole number of at least 1."
  }
}

variable "allow_unauthenticated_gateways" {
  type        = bool
  description = "Whether a gateway may set authentication = false. Set in defaults.auto.tfvars."
}
