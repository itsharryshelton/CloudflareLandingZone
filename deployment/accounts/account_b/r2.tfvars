# Account: account_b - R2 buckets. Consumed by the r2 layer only.
#
#   terraform -chdir=layers/r2 plan \
#     -var-file=../../accounts/account_b/account.tfvars \
#     -var-file=../../accounts/account_b/zones.tfvars \
#     -var-file=../../accounts/account_b/r2.tfvars
#
# See accounts/account_a/r2.tfvars for the fuller worked example.

r2_buckets = {
  # Cache bucket, pinned to Western Europe and emptied weekly. Everything in it
  # is regenerable, which is why an empty prefix on the expiry rule is deliberate here.
  render_cache = {
    name     = "account-b-render-cache"
    location = "weur"

    lifecycle_rules = [
      {
        id                                 = "abort-incomplete-multipart-uploads"
        prefix                             = ""
        abort_multipart_uploads_after_days = 1
      },
      {
        id                        = "expire-renders"
        prefix                    = "renders/"
        delete_objects_after_days = 7
      },
    ]
  }
}
