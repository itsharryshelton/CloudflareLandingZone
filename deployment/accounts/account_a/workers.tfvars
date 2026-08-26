# Account: account_a - Workers and Workers KV. Consumed by the workers layer only.
#
#   terraform -chdir=layers/workers plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
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
}
