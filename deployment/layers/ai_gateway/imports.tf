# Adopting AI gateways and dynamic routes that already exist.
#
# WHY THIS FILE EXISTS
# Gateways are usually created in the dashboard the first time somebody points
# an SDK at one. A gateway ID is unique per account, so the first apply of this
# layer against one that already exists does not create a duplicate - it fails,
# after the plan was approved. List what is there first:
#
#   curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
#     "https://api.cloudflare.com/client/v4/accounts/<account_id>/ai-gateway/gateways?per_page=50" \
#     | jq -r '.result[] | [.id, .authentication, .collect_logs, .is_default] | @tsv'
#
# and, per gateway, its dynamic routes:
#
#   curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
#     "https://api.cloudflare.com/client/v4/accounts/<account_id>/ai-gateway/gateways/<gateway_id>/routes" \
#     | jq -r '(.data.routes // .result.routes // [])[] | [.id, .name] | @tsv'
#
# If that returns gateways matching ai_gateway.tfvars, uncomment the blocks
# below. The gateway import id is "<account_id>/<gateway_id>" and the route one
# is "<account_id>/<gateway_id>/<route_id>" - the route's generated ID, not its
# name. `import` blocks are resolved at plan time, so the saved plan the
# pipeline applies already carries the import - no `terraform import` CLI run
# and no local init.
#
# Read the first plan after this lands before approving it. It reconciles what
# is at Cloudflare today against ai_gateway.tfvars, so a setting somebody
# changed in the dashboard shows up there as a change back. Three of those are
# worth looking for by name:
#   - workers_ai_billing_mode. Provider 5.23 can only send "postpaid", so a
#     gateway switched to Unified Billing in the dashboard is switched back by
#     the first apply that touches it, and the plan shows it as a one-word diff.
#   - spend_limits. A rule is matched by its ID, which is the key in
#     spend_limits. Give each adopted rule the ID it already has as its key, or
#     the apply replaces the rule with a new one under a new ID.
#   - a route's elements. Import a route only once its elements in
#     ai_gateway.tfvars match the dashboard's JSON view exactly. Element changes
#     normally replace the route (see modules/ai_gateway/main.tf), but an
#     import creates the revision hash that triggers that from scratch, and a
#     new hash does not trigger anything. So an adopted route whose elements
#     differ shows an in-place update instead - one the API ignores, on every
#     plan. If that happens, remove the import, delete the route in the
#     dashboard and let this layer create it; requests naming it fail in the
#     gap.
#
# A route containing a percentage split cannot be adopted at all: the provider
# cannot represent that element type. Leave such a route out of this layer.
#
# "default" is the gateway Cloudflare creates for the first authenticated
# request that names none, with authentication and logging on. On most
# accounts using AI Gateway it already exists, so declaring gateway_id =
# "default" means importing it. Destroying it is undone by the next such
# request, which recreates it with those settings, not these.
#
# import {
#   for_each = {
#     # <logical key in ai_gateways> = "<existing gateway id>"
#     # support_assistant = "support-assistant"
#   }
#
#   to = module.ai_gateway[each.key].cloudflare_ai_gateway.this
#   id = "${var.cloudflare_account_id}/${each.value}"
# }
#
# The route block takes objects rather than a "<key>/<route>" string to split,
# because an import's `to` address may not call a function.
#
# import {
#   for_each = {
#     # <any unique label> = { gateway = "<logical key in ai_gateways>", route = "<route name>", id = "<existing route id>" }
#     # support_default = { gateway = "support_assistant", route = "support-default", id = "0123abcd" }
#   }
#
#   to = module.ai_gateway[each.value.gateway].cloudflare_ai_gateway_dynamic_routing.this[each.value.route]
#   id = "${var.cloudflare_account_id}/${local.gateways[each.value.gateway].gateway_id}/${each.value.id}"
# }
