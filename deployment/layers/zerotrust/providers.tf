# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer, all at account level:
#   Access: Organizations, Identity Providers, and Groups:Edit
#   Access: Apps and Policies:Edit
#   Access: Service Tokens:Edit
#
# One secret does not come through this token. An identity provider's OAuth
# client secret - the Entra ID app registration's - arrives separately as
# TF_VAR_identity_provider_secrets. See variables.tf.
provider "cloudflare" {}
