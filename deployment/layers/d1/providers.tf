# The token is read from CLOUDFLARE_API_TOKEN
#
# Minimum token scope for this layer:
#   Account D1:Edit   the databases, the name lookup in imports.tf, and the
#                     migration step that runs after apply with this same
#                     token - wrangler applies a migration through D1's query
#                     endpoint, which takes Edit
#
# Nothing zone-scoped. A D1 database is reached only through a Worker binding,
# which the workers layer writes with its own token, so this one can create and
# alter databases but cannot put one in front of any request.
#
# It can read and change every row in every database on the account, which is
# a bigger capability than "creates databases" sounds. Keep it scoped to this
# layer's environment and do not reuse it for the workers layer, which only
# needs D1:Read to resolve a database name to its UUID.
provider "cloudflare" {}
