terraform {
  # Deliberately lower than the deployment layers, which require 1.11 because
  # their R2 backend needs `use_lockfile`. A module owns no backend and uses
  # nothing newer than 1.5, so keeping the floor here lets the module be
  # consumed by a root module on an older Terraform. Do not raise it to match
  # the layers.
  required_version = ">= 1.5.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.7"
    }
  }
}
