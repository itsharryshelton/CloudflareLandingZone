# The account's existing Zero Trust organization.
#
# Read for two reasons. It is how the layer adopts a team name somebody chose in
# the dashboard rather than insisting one be restated in an account tree, and it
# is what makes the team-name-change guardrail in preflight.tf possible: without
# it, a typo in zero_trust_team_name would plan as a clean update and apply as a
# rename of the whole team domain.
#
# THIS IS ALSO THE LAYER'S BOOTSTRAP CHECK, and it does not fail politely. On an
# account that has never enabled Zero Trust there is no organisation to read, and
# this data source fails during plan with Cloudflare's own message rather than a
# precondition of ours - a data source that errors takes the run with it before
# anything in preflight.tf is evaluated.
#
# It cannot be avoided from here. The provider's cloudflare_zero_trust_organization
# resource creates with an HTTP PUT, not a POST, so Terraform can adopt and manage
# an organization but cannot bring one into being. Choosing the team name is a
# one-off, out of band:
#
#   Dashboard: Zero Trust, then Settings, then Custom Pages. Cloudflare asks for
#   the team name the first time the section is opened.
#
#   API: POST https://api.cloudflare.com/client/v4/accounts/<account_id>/access/organizations
#        {"name": "Acme Internal Applications", "auth_domain": "acme.cloudflareaccess.com"}
#
# Do it once, set zero_trust_team_name to match, and this layer owns the
# organization from then on. GETTING_STARTED.md has the same instructions in the
# place an operator will look for them.
data "cloudflare_zero_trust_organization" "this" {
  account_id = var.cloudflare_account_id
}
