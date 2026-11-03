# Account: account_a - Workers, Workers KV and queues. Consumed by the workers
# layer only. D1 databases are declared in d1.tfvars and bound here by key.
#
#   terraform -chdir=layers/workers plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/d1.tfvars \
#     -var-file=../../accounts/account_a/workers.tfvars
#
# Worker scripts reside in deployment/layers/workers/scripts/ and are referenced by
# relative path. Secrets are resolved via Cloudflare Secrets Store references.

# ---------------------------------------------------------------------------
# KV Namespaces
# ---------------------------------------------------------------------------
# `pairs` is left unset for dynamic datasets so Terraform manages only the namespace
# resource whilst data is loaded via `wrangler kv bulk put` in CI/CD pipelines.

kv_namespaces = {
  config = {
    title = "account-a-config"
  }

  cache = {
    title = "account-a-cache"
  }
}

# ---------------------------------------------------------------------------
# Queues
# ---------------------------------------------------------------------------
# The producer side is a binding on the Worker that writes (see
# telemetry_processor below); the consumer side is declared here, because a queue
# takes exactly one.

queues = {
  telemetry = {
    name = "account-a-telemetry"

    consumer = {
      # Resolved to the deployed Worker's name, which is also what makes
      # Terraform deploy it before attaching the consumer.
      worker_key            = "telemetry_processor"
      dead_letter_queue_key = "telemetry_dlq"

      settings = {
        batch_size       = 50
        max_wait_time_ms = 5000
        max_retries      = 3
        retry_delay      = 30
      }
    }
  }

  telemetry_dlq = {
    name = "account-a-telemetry-dlq"

    # No consumer on purpose, and exempt from allow_queues_without_consumer
    # because another queue dead letters into it: this is the holding pen for
    # batches that failed three times, kept for the full fortnight so there is
    # something to look at on Monday.
    message_retention_period = 1209600
  }
}

# ---------------------------------------------------------------------------
# Workers
# ---------------------------------------------------------------------------
# Each Worker defines its entry script, bindings, routes, custom domains, or cron triggers.
# Secrets Store references are used for sensitive tokens to avoid plaintext in state.

worker_scripts = {
  security_headers = {
    name        = "account-a-security-headers"
    script_file = "headers/security_headers.js"

    bindings = [
      {
        name             = "CONFIG"
        type             = "kv_namespace"
        kv_namespace_key = "config"
      },
      {
        name        = "API_SECRET"
        type        = "secrets_store_secret"
        store_id    = "0123456789abcdef0123456789abcdef"
        secret_name = "telemetry-api-key"
      },
    ]

    routes = [
      {
        zone_key = "primary"
        pattern  = "example.com/*"
      },
      {
        zone_key = "primary"
        pattern  = "www.example.com/*"
      },
    ]
  }

  # Producer and consumer in one Worker: the fetch handler accepts an event and
  # returns immediately, and the queue handler writes the batch to D1 minutes
  # later if that is when capacity allows. Nothing a visitor waits on depends on
  # the database being up.
  #
  # It has no route of its own here - it is invoked by the queue. Give it one the
  # same way security_headers has, plus a proxied DNS record in dns.tfvars, where
  # the ingest endpoint should be reachable from outside.
  telemetry_processor = {
    name        = "account-a-telemetry-processor"
    script_file = "queues/telemetry_processor.js"

    bindings = [
      {
        name      = "TELEMETRY_QUEUE"
        type      = "queue"
        queue_key = "telemetry"
      },
      {
        # A key from d1.tfvars. The d1 layer creates the database; this layer
        # finds it by name.
        name            = "TELEMETRY_DB"
        type            = "d1"
        d1_database_key = "telemetry"
      },
    ]
  }
}
