# tflint-ignore-file: terraform_unused_declarations

# Apply tier, read by .github/scripts/tf-matrix.sh. See the same file under
# deployment/layers/account_governance for what this local is and why it exists.
#
# This layer is tier 3, behind the tier that creates zones. Access applications
# are addressed by hostname rather than by zone ID, so the zone must exist
# before they are written - but the layer never reads one, so there is no
# data "cloudflare_zone" block for the derivation to find.
locals {
  apply_tier = 3
}
