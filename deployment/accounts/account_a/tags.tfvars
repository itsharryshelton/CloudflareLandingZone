# Account: account_a - Cloudflare resource tags. Consumed by the zones,
# zerotrust, r2 and workers layers, each of which tags only the resources it
# owns, from its own section below.
#
# Precedence, later wins:
#   defaults -> <type>.defaults -> <type>.resources[<key>] -> pipeline keys
#
# - Resource keys are the logical keys from zones.tfvars, zerotrust.tfvars,
#   r2.tfvars and workers.tfvars - not names, not IDs.
# - A null value drops a key an earlier level set.
# - `managed-by` and `layer` are set by the pipeline on every resource and
#   cannot be set here.
# - Cloudflare replaces a resource's whole tag set on every write, so a tag
#   added in the dashboard to a resource listed here is removed on the next apply.

resource_tags = {
  # Every resource of every type, unless a later level overrides it.
  defaults = { team = "platform" }

  # A value outside its list fails the plan, so "prod" and "production" cannot
  # split one filter into two.
  allowed_values = {
    environment = ["dev", "stage", "prod"]
    team        = ["platform", "web", "security"]
  }

  # ---------------------------------------------------------------------------
  # Zones
  # ---------------------------------------------------------------------------
  zones = {
    # Any zone not listed below is tagged prod.
    defaults = { environment = "prod" }

    resources = {
      primary     = { team = "web" }
      test_domain = { environment = "dev" }
    }
  }

  # ---------------------------------------------------------------------------
  # Access applications. No type default - dev, stage and prod applications
  # tend to sit side by side, so each states its own environment.
  # ---------------------------------------------------------------------------
  access_applications = {
    resources = {
      grafana = { environment = "prod" }
    }
  }

  # ---------------------------------------------------------------------------
  # R2 buckets
  # ---------------------------------------------------------------------------
  r2_buckets = {
    defaults = { environment = "prod" }

    resources = {
      public_assets = { team = "web" }
      log_archive   = { team = "security" }
    }
  }

  # ---------------------------------------------------------------------------
  # KV namespaces
  # ---------------------------------------------------------------------------
  kv_namespaces = {
    defaults = { environment = "prod" }

    resources = {
      # Shared by every environment, so the type default is dropped rather than
      # tagging it as one of them.
      cache = { environment = null }
    }
  }

  # ---------------------------------------------------------------------------
  # D1 databases
  # ---------------------------------------------------------------------------
  d1_databases = {
    defaults = { environment = "prod" }

    resources = {
      telemetry = { team = "platform" }
    }
  }

  # ---------------------------------------------------------------------------
  # Queues
  # ---------------------------------------------------------------------------
  queues = {
    defaults = { environment = "prod" }

    resources = {
      telemetry     = { team = "platform" }
      telemetry_dlq = { team = "platform" }
    }
  }

  # ---------------------------------------------------------------------------
  # Workers
  # ---------------------------------------------------------------------------
  worker_scripts = {
    resources = {
      security_headers    = { environment = "prod", team = "web" }
      telemetry_processor = { environment = "prod", team = "platform" }
    }
  }
}
