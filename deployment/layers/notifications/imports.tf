# Adopting notification policies and webhooks that already exist.
#
# WHY THIS FILE EXISTS
# Most accounts already have policies: somebody ticked "notify me" in the
# dashboard for a certificate or an origin error long before this layer. Applied
# against those, this layer does not fail - Cloudflare allows two policies with
# the same name and alert type - it creates a second copy, and every alert then
# arrives twice, once from a policy nobody manages. Check the account before the
# first apply of this layer:
#
#   curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
#     "https://api.cloudflare.com/client/v4/accounts/<account_id>/alerting/v3/policies" \
#     | jq -r '.result[] | [.id, .alert_type, .name, .enabled] | @tsv'
#
#   curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
#     "https://api.cloudflare.com/client/v4/accounts/<account_id>/alerting/v3/destinations/webhooks" \
#     | jq -r '.result[] | [.id, .type, .name] | @tsv'
#
# The second query returns each webhook's URL as well; it is left out above
# because for a chat service the URL is the credential. Do not paste the full
# response into a ticket or a pull request.
#
# For anything that matches what notifications.tfvars declares, uncomment the
# blocks below and map each logical key to its EXISTING ID. Both import ids are
# "<account_id>/<id>". `import` blocks are resolved at plan time, so the saved
# plan the pipeline applies already carries the import - no `terraform import`
# CLI run and no local init.
#
# Read the first plan after this lands before approving it. It reconciles what
# is at Cloudflare today against notifications.tfvars: a recipient somebody
# added in the dashboard shows up there as a removal, and an adopted webhook
# shows its secret as a change, because Cloudflare never returns one.
#
# A policy that does not match anything declared is left alone - this layer
# never deletes what it does not manage. Delete it in the dashboard, or declare
# and import it first if it should be kept.
#
# Once everything is in state this file can be emptied again.
#
# import {
#   for_each = {
#     # <logical key in notification_webhooks> = "<existing webhook id>"
#     # noc_slack = "0123456789abcdef0123456789abcdef"
#   }
#
#   to = module.notifications.cloudflare_notification_policy_webhooks.this[each.key]
#   id = "${var.cloudflare_account_id}/${each.value}"
# }
#
# import {
#   for_each = {
#     # <logical key in notification_policies> = "<existing policy id>"
#     # cloudflare_incidents = "0123456789abcdef0123456789abcdef"
#   }
#
#   to = module.notifications.cloudflare_notification_policy.this[each.key]
#   id = "${var.cloudflare_account_id}/${each.value}"
# }
