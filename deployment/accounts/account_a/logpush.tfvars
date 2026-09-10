# Account: account_a - Logpush. Consumed by the logpush layer only.
#
#   terraform -chdir=layers/logpush plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/logpush.tfvars
#
# ENTERPRISE ONLY. On an account without Logpush, leave `logpush_jobs = {}`.
#
# NO CREDENTIAL GOES IN THIS FILE. A destination that carries one - R2 keys, a
# Splunk HEC token, a Datadog API key, an Azure SAS - leaves destination_conf out
# here, and the whole URI is set as the TF_VAR_LOGPUSH_DESTINATION_SECRETS secret
# in the account_a-plan environment, keyed by job:
#
#   {"audit_archive":"r2://...","gateway_http_siem":"splunk://..."}
#
logpush_jobs = {
  # The account audit trail
  audit_archive = {
    name    = "account-a-audit-archive"
    dataset = "audit_logs"

    # From TF_VAR_logpush_destination_secrets, because an R2 destination carries
    # its access key:
    #   r2://account-a-log-archive/audit/{DATE}?account-id=<account id>&access-key-id=<key id>&secret-access-key=<secret>

    output_options = {
      field_names = [
        "When", "ID", "ActionType", "ActionResult",
        "ActorType", "ActorID", "ActorEmail", "ActorIP", "Interface",
        "OwnerID", "ResourceType", "ResourceID",
        "OldValue", "NewValue", "Metadata",
      ]
    }
  }

  # Gateway HTTP decisions to the SOC's Splunk
  gateway_http_siem = {
    name    = "account-a-gateway-http"
    dataset = "gateway_http"

    # From TF_VAR_logpush_destination_secrets - the HEC token rides in a header:
    #   splunk://<endpoint>?channel=<channel id>&sourcetype=<source type>&header_Authorization=<HEC token>

    # The shortest interval Cloudflare allows, so a blocked request reaches the
    # SIEM while it is still worth triaging.
    max_upload_interval_seconds = 30

    output_options = {
      field_names = [
        "Datetime", "RequestID", "Action", "PolicyID", "PolicyName",
        "Email", "UserID", "DeviceID", "SourceIP",
        "DestinationIP", "DestinationPort", "HTTPHost", "HTTPMethod", "URL",
        "HTTPStatusCode", "UserAgent", "CategoryNames", "ApplicationNames",
        "BlockedFileName", "BlockedFileReason",
      ]
    }
  }

  # A zone-scoped job needs its zone on Enterprise, currently not setting any zones as Enterprise on this example.
  #
  # An S3 destination carries no credential - the bucket policy lets
  # Cloudflare's Logpush user put objects - so it is committed here. Cloudflare
  # asks for an ownership challenge before creating the job; the token is set as
  # the TF_VAR_LOGPUSH_OWNERSHIP_CHALLENGES secret in the account_a-plan
  # environment:
  #   {"primary_http_requests":"<contents of the challenge file Cloudflare wrote to the bucket>"}
  #
  # primary_http_requests = {
  #   name             = "example-com-http-requests"
  #   dataset          = "http_requests"
  #   zone_key         = "primary"
  #   destination_conf = "s3://example-com-logs/http_requests/{DATE}?region=eu-west-2&sse=AES256"
  #
  #   # Health checks are most of the volume and none of the interest.
  #   filter = <<-JSON
  #     {"where":{"and":[{"key":"ClientRequestPath","operator":"!eq","value":"/healthz"}]}}
  #   JSON
  #
  #   output_options = {
  #     field_names = [
  #       "EdgeStartTimestamp", "RayID", "ClientIP", "ClientCountry", "ClientASN",
  #       "ClientRequestHost", "ClientRequestMethod", "ClientRequestURI",
  #       "ClientRequestUserAgent", "EdgeResponseStatus", "OriginResponseStatus",
  #       "CacheCacheStatus", "SecurityAction", "SecurityRuleID", "BotScore",
  #       "WAFAttackScore",
  #     ]
  #   }
  # }
}
