# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer:
#   Account  Cloudflare Pages:Edit  - projects, their deployment configs and
#                                     custom domains
#   Zone     Zone:Read              - so data.cloudflare_zone can resolve a key
#                                     to its ID; only if a custom domain names a
#                                     zone_key
#   Zone     DNS:Edit               - the CNAME behind each such custom domain
#
# Pages:Edit is bigger than it reads. It can change what a production site
# serves - by repointing the Git source, or by a Direct Upload of any build -
# and it can read every project's plain env vars. Keep it off the workers and
# zones tokens.
#
# It needs NOTHING in Zero Trust. Access applications for these projects are
# written by the zerotrust layer with its own token; this layer only reports the
# hostnames they must cover (see outputs.tf).
provider "cloudflare" {}
