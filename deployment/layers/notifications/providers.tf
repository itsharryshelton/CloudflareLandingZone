# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer:
#   Account  Notifications:Edit - policies and webhook destinations (the API
#                                 names the same grant Notifications Write)
#   Zone     Zone:Read          - only if a policy names a zone_key, so
#                                 data.cloudflare_zone can resolve it to an ID
#
# Notifications:Edit cannot change anything a policy watches. It can do two
# things worth knowing about: point any alert at a destination of its choosing,
# which reads the account's incident traffic, and switch a policy off, which
# silences it. Reading a webhook never returns its secret, but the plan token's
# Notifications:Read does return its URL - which, for a chat service, is the
# credential.
provider "cloudflare" {}
