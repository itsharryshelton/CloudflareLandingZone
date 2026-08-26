#The token is read from CLOUDFLARE_API_TOKEN
#
# Minimum token scope for this layer:
#   Account Filter Lists:Edit   the Bulk Redirect Lists, and any rows this layer
#                               manages inline
#   Account Rulesets:Edit       the http_request_redirect entry-point ruleset
#                               that switches each list on
#
# Nothing at zone scope. Bulk Redirects are an account-level product: each row
# carries its own hostname, and the rule is evaluated for every zone in the
# account. That is convenient and is also the risk - this token can redirect any
# hostname the account serves, including one belonging to a different brand, so
# it is not a token to share with a layer that only needs to read.
#
# The load step that writes rows needs the same Account Filter Lists:Edit and
# nothing more. It does NOT need Rulesets:Edit, so the pipeline identity that
# loads redirect data cannot also change which lists are live.
provider "cloudflare" {}
