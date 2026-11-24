terraform {
  # 1.12 is the floor because guards in this module rely on `||` and `&&`
  # short-circuiting, which Terraform only does from 1.12. On anything older, a
  # check such as `x == null || contains(list, x)` still evaluates the right-hand
  # side and fails on the very null it was written to skip.
  required_version = ">= 1.12.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.7"
    }
  }
}
