# Account: account_b - Logpush. Consumed by the logpush layer only.
#
#   terraform -chdir=layers/logpush plan \
#     -var-file=../../accounts/account_b/account.tfvars \
#     -var-file=../../accounts/account_b/zones.tfvars \
#     -var-file=../../accounts/account_b/logpush.tfvars
#
# See accounts/account_a/logpush.tfvars for the fuller worked example.
#
# ENTERPRISE ONLY. On an account without Logpush, leave `logpush_jobs = {}`.
#
# The account audit trail to Google Cloud Storage. A gs:// destination carries
# no credential - Cloudflare's Logpush service account is granted write on the
# bucket - so it is committed here. Cloudflare asks for an ownership challenge
# before creating the job; the token is set as the
# TF_VAR_LOGPUSH_OWNERSHIP_CHALLENGES secret in the account_b-plan environment:
#   {"audit_archive":"<contents of the challenge file Cloudflare wrote to the bucket>"}

logpush_jobs = {
  audit_archive = {
    name             = "account-b-audit-archive"
    dataset          = "audit_logs"
    destination_conf = "gs://account-b-audit-logs/audit/{DATE}"

    output_options = {
      field_names = [
        "When", "ID", "ActionType", "ActionResult",
        "ActorType", "ActorID", "ActorEmail", "ActorIP", "Interface",
        "OwnerID", "ResourceType", "ResourceID",
        "OldValue", "NewValue", "Metadata",
      ]
    }
  }
}
