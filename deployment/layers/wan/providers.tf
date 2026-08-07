#The token is read from CLOUDFLARE_API_TOKEN
#
# Minimum token scope for this layer: Account Magic Transit:Edit.
#
# The permission group is named after the older product and covers the whole
# /accounts/<id>/magic/ API surface
#
# Two things the token deliberately does not carry. It has no Magic Firewall
# permission, so it cannot write a packet filter rule. And it has no account
# membership permission, so it cannot hand anybody access to the account.
#
# What it CAN do is worth stating plainly, because it is a networking credential
# rather than a web one: it can delete a tunnel, which takes a site off the
# network, and it can change a static route, which sends a site's traffic
# somewhere else. Treat its reviewer list the way you treat account_governance.
provider "cloudflare" {}
