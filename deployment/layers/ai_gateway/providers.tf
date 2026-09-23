# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer, at account level:
#   AI Gateway:Edit   (the API refers to the same grant as AI Gateway Write)
#
# That grant reaches AI Gateway and nothing else: it cannot read a zone, touch
# a rule or change Zero Trust. It does not include AI Gateway Run, so it cannot
# send traffic through a gateway either.
#
# It CAN read and delete every gateway's logs, and those logs are prompts and
# responses. So can AI Gateway Read, which the shared plan token carries along
# with every other Read group - Cloudflare has no narrower grant that reads a
# gateway's settings without its logs. Anyone holding either token can read
# whatever users typed into anything behind a logging gateway. Keep that in
# mind when deciding what collect_logs is set to, and who can reach the
# <account>-plan environment.
#
# BYOK provider keys are a different permission (Secrets Store Write) and are
# not managed by this layer at all - see ai_gateway.tf.
provider "cloudflare" {}
