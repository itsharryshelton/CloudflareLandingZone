# Account: account_a - R2 buckets. Consumed by the r2 layer only.
#
#   terraform -chdir=layers/r2 plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/r2.tfvars
#
# The Terraform state bucket does NOT belong here. A layer that manages the
# bucket its own state lives in can propose destroying it, if you do add... be careful :D
#
# A custom_domains hostname must NOT also appear in dns.tfvars - you do not need to add it to dns.tfvars!

r2_buckets = {
  # Private bucket, read server-side over the S3 API. No CORS, no public hostname.
  app_uploads = {
    name = "account-a-app-uploads"

    lifecycle_rules = [
      {
        id                                 = "abort-incomplete-multipart-uploads"
        prefix                             = ""
        abort_multipart_uploads_after_days = 7
      },
      # Raw uploads are processed within a day and are not the system of record.
      {
        id                        = "expire-raw-uploads"
        prefix                    = "raw/"
        delete_objects_after_days = 30
      },
      # Thumbnails are regenerable, so they move to the cheaper class rather than being deleted.
      {
        id                                         = "cool-thumbnails"
        prefix                                     = "thumbnails/"
        transition_to_infrequent_access_after_days = 90
      },
    ]
  }

  # Public static assets, served from a hostname in the primary zone - WAF Rules etc will apply if you use public addresses
  public_assets = {
    name = "account-a-public-assets"

    cors_rules = [
      {
        id              = "web-app-read"
        allowed_origins = ["https://app.example.com", "https://www.example.com"]
        allowed_methods = ["GET", "HEAD"]
        max_age_seconds = 3600
      },
    ]

    custom_domains = [
      { zone_key = "primary", hostname = "assets.example.com" },
    ]
  }

  # Log archive. Retained for a year and locked for the same period, so nothing -
  # including this pipeline - can delete an object before its retention expires.
  log_archive = {
    name          = "account-a-log-archive"
    storage_class = "InfrequentAccess"

    lifecycle_rules = [
      {
        id                                 = "abort-incomplete-multipart-uploads"
        prefix                             = ""
        abort_multipart_uploads_after_days = 7
      },
      {
        id                        = "expire-working-copies"
        prefix                    = "working/"
        delete_objects_after_days = 30
      },
    ]

    lock_rules = [
      {
        id              = "retain-audit-logs-for-a-year"
        prefix          = "audit/"
        retain_for_days = 365
      },
    ]
  }
}
