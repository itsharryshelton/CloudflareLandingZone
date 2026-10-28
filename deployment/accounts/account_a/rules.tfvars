# Account: Your-Org - cache, transform, origin, redirect and config rules. Consumed by the rules layer only.
#
#   terraform -chdir=layers/rules plan \
#     -var-file=../../accounts/your-org/account.tfvars \
#     -var-file=../../accounts/your-org/zones.tfvars \
#     -var-file=../../accounts/your-org/rules.tfvars
rule_policies = {
  primary = {
    zone_key = "primary"
    cache_rules = [
      {
        # Cache based on cookie test_primary
        name        = "Cache everything for anonymous visitors"
        description = "Cache everything for anonymous visitors, ignoring query strings"
        expression  = "not http.cookie contains \"test_primary\""
        enabled     = true
        cache       = true
        cache_key = {
          custom_key = {
            query_string = {
              exclude = { all = true }
            }
          }
        }
      },
      {
        # Signed, single-use URLs. Caching one serves another visitor a file they
        name       = "Bypass cache for tokenised downloads"
        expression = "http.request.uri.path contains \"/download\" and http.request.uri.query contains \"token=\""
        cache      = true
      },
      {
        # Bypass Cache for Debug Paths
        name       = "Bypass cache for origin debug paths"
        expression = "http.request.uri.path contains \"origin\""
        cache      = true
      },
    ]

    # Applied after the security phases
    transform_rules = [
      {
        # Strips a header a client can forge.
        name       = "Remove client-supplied Forwarded header"
        expression = "true"
        enabled    = false
        headers = {
          "Forwarded" = { operation = "remove" }
        }
      },
    ]

    # Per-hostname SSL override, left commented out because it is an emergency
    # tool rather than a standing setting. The zone runs strict, so a proxied
    # hostname whose origin has no certificate valid for its name gets a 526.
    # Uncomment this for the affected hostname only, rather than lowering the
    # whole zone, and delete it again once the origin's certificate is valid.
    # full still encrypts, but accepts any certificate.
    #
    # A hostname on a zone with no policy here needs a policy of its own for
    # that zone, holding only config_rules.
    #
    # config_rules = [
    #   {
    #     name       = "Temporary SSL full - app.example.com"
    #     expression = "http.host eq \"app.example.com\""
    #     ssl        = "full"
    #   },
    # ]
  }
}
