#The token is read from CLOUDFLARE_API_TOKEN
#
# Minimum token scope for this layer:
#   Account Workers Scripts:Edit      the Worker itself, its bindings and its
#                                     cron triggers
#   Account Workers KV Storage:Edit   the namespaces, and any pairs this layer
#                                     manages
#   Account D1:Edit                   the databases, but not the rows in them -
#                                     a migration step needs its own token
#   Account Queues:Edit               the queues and their consumers
#   Zone Workers Routes:Edit          only if var.worker_scripts declares routes
#   Zone:Read                         so data.cloudflare_zone can resolve a zone
#                                     key to its ID
#
# A Worker on a route sits in front of the origin for every request it matches,
# so this token can change what a site returns without touching DNS or the
# origin. It is a bigger capability than the resource list suggests - keep it
# separate from the zones layer's token rather than reusing one that already has
# Zone:Edit.
#
# The token does NOT need DNS:Edit for routes. It does for custom domains, which
# Cloudflare implements by writing the record itself; grant Zone DNS:Edit only
# where var.worker_scripts declares one.
#
# Bindings deliberately do not need scope over what they point at. Binding a KV
# namespace or an R2 bucket is a Workers Scripts operation, so this token can
# wire a Worker to a bucket without holding any permission over the bucket's
# contents.
provider "cloudflare" {}
