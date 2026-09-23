# Layer ai_gateway - platform baseline. Auto-loaded from this directory.

# The account ID and gateway ID in a gateway's URL are not secrets, so an
# unauthenticated gateway is open to anyone who guesses the second. Callers need
# a token with AI Gateway Run, which is a credential for the application.
default_authentication = true

# Cloudflare's own default, and what analytics, the log explorer and Logpush are
# built on. Logs are full prompts and responses: a gateway in front of anything
# sensitive states collect_logs = false, or uses DLP to keep that data out.
default_collect_logs = true

# What the API gives a gateway created without these. DELETE_OLDEST keeps logging
# at the cap; STOP_INSERTING stops recording, and stops Logpush exporting, until
# someone deletes logs by hand. Workers Free holds 100000 logs per account.
default_log_storage = {
  max_logs  = 10000000
  when_full = "DELETE_OLDEST"
}

# Cloudflare's Workers Paid ceiling; 10 on Workers Free.
max_ai_gateways = 20

# Turning authentication off opens the gateway to anyone. It takes a pull request
# that says why.
allow_unauthenticated_gateways = false
