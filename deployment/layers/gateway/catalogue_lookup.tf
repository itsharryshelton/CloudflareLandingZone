# Cloudflare's own catalogues of content categories, security categories and
# applications.
#
# Gateway expressions are written in numeric identifiers: `any(app.ids[*] in
# {606})`, `any(dns.content_category[*] in {68 80})`. The numbers are stable, but
# they are documented nowhere an operator would look, they change as Cloudflare
# adds categories and applications, and a wrong one is a rule that silently
# matches nothing rather than an error. So an account tree names things, and this
# resolves the names.
#
# Both need Zero Trust:Read on the account token and nothing else.

data "cloudflare_zero_trust_gateway_categories_list" "this" {
  account_id = var.cloudflare_account_id
}

# The endpoint returns applications and the app types they belong to in one list.
# `id` is what `app.ids` matches on, which is the field this layer uses:
# selecting "Microsoft 365" covers every hostname Cloudflare knows the product
# uses, which is the difference between one bypass rule and forty.
data "cloudflare_zero_trust_gateway_app_types_list" "this" {
  account_id = var.cloudflare_account_id
}
