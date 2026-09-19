# Adopting Turnstile widgets that already exist.
#
# WHY THIS FILE EXISTS
# A widget's sitekey is embedded in pages this repository does not manage. If a
# widget already exists at Cloudflare and this layer creates its own instead,
# the apply succeeds, the plan looks clean, and every form still carrying the old
# sitekey is now protected by a widget nobody is validating against - or fails
# outright, depending on which half of the pair the backend has. Terraform cannot
# detect any of that. Check the dashboard before the first apply of this layer:
#
#   curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
#     "https://api.cloudflare.com/client/v4/accounts/<account_id>/challenges/widgets" \
#     | jq -r '.result[] | [.sitekey, .name, (.domains | join(","))] | @tsv'
#
# If that returns widgets matching what turnstile.tfvars declares, uncomment the
# block below and map each logical key to its EXISTING sitekey. The import id is
# "<account_id>/<sitekey>". `import` blocks are resolved at plan time, so the
# saved plan the pipeline applies already carries the import - no `terraform
# import` CLI run and no local init.
#
# Read the first plan after this lands before approving it. It reconciles what is
# at Cloudflare today against turnstile.tfvars, and a hostname somebody added in
# the dashboard shows up there as a removal.
#
# Once every widget is in state this file can be deleted - unlike the gateway
# import, nothing here is a singleton that cannot be created.
#
# import {
#   for_each = {
#     # <logical key in turnstile_widgets> = "<existing sitekey>"
#     # primary   = "0x4AAAAAAA..."
#     # marketing = "0x4AAAAAAA..."
#   }
#
#   to = module.turnstile.cloudflare_turnstile_widget.this[each.key]
#   id = "${var.cloudflare_account_id}/${each.value}"
# }
