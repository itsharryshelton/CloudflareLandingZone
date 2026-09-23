terraform {
  # 1.12 is the floor because guards in this module rely on `||` and `&&`
  # short-circuiting, which Terraform only does from 1.12. On anything older, a
  # check such as `x == null || contains(list, x)` still evaluates the right-hand
  # side and fails on the very null it was written to skip.
  required_version = ">= 1.12.0"

  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      # Higher than the ~> 5.7 every other module takes, deliberately. Neither
      # cloudflare_ai_gateway nor cloudflare_ai_gateway_dynamic_routing exists
      # before 5.19.0, and guardrails and spend_limits arrived in 5.20.0. On an
      # older provider the failure is "resource type not supported", which says
      # nothing about why.
      version = "~> 5.20"
    }
  }
}
