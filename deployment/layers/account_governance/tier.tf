# tflint-ignore-file: terraform_unused_declarations

# Apply tier, read by .github/scripts/tf-matrix.sh. Nothing in Terraform
# consumes this local - it exists so the one ordering fact the source cannot
# express lives with the layer it describes rather than in a list inside the
# pipeline, where renaming or retiring a layer leaves a stale entry behind.
#
# Tier numbers are the ones the apply workflow's job names and the READMEs use:
# tier 1 applies first. A layer whose tier is derivable carries no tier.tf, and
# most do: creating zones puts a layer in tier 2, resolving one with
# data "cloudflare_zone" puts it in tier 3.
#
# This layer is tier 1, on its own and ahead of everything. Account-wide
# permissions and resource-group scope are what every later layer's token is
# evaluated against, and no Terraform reference expresses that - the dependency
# is on the API's authorisation decision, not on an attribute.
locals {
  apply_tier = 1
}
