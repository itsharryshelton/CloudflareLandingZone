# The token is read from CLOUDFLARE_API_TOKEN. Never put it in a .tf or .tfvars.
#
# Minimum token scope for this layer, at zone scope. Cloudflare gates each
# ruleset phase behind its own permission group, so it is one Edit per phase
# (the API's name for the same group in brackets):
#   Cache Rules:Edit       http_request_cache_settings    (Cache Settings Write)
#   Transform Rules:Edit   http_request_late_transform    (Zone Transform Rules Write)
#   Origin Rules:Edit      http_request_origin            (Origin Write)
#   Single Redirect:Edit   http_request_dynamic_redirect  (Dynamic URL Redirects Write)
#   Config Rules:Edit      http_config_settings           (Config Settings Write)
#   Zone:Read              so data.cloudflare_zone can resolve a zone key
#                          to its ID
#
# A missing group fails only its own phase: without Origin Rules:Edit, a zone's
# first http_request_origin ruleset failed with `403 request is not authorized`
# while cache rules in the same apply succeeded. So a token that predates a
# phase looks healthy until that phase is first used.
#
# Not Zone Settings:Edit. A config rule overrides the zone's SSL mode for the
# requests it matches without that grant, so this token can weaken TLS to the
# origin for any hostname on the zones it covers.
provider "cloudflare" {}
