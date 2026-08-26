# Builds the rules-language expressions and the provider-shaped rule list.
#
# Expression construction is here rather than in a calling layer deliberately: a
# layer that hand-writes rules language is a layer that can emit a syntactically
# valid expression which silently matches nothing, and there is no plan-time
# feedback for that. One place to get it right, and one place to fix it.

locals {
  # `format` rather than interpolation. The rules language refers to a list as
  # `$name`, and "$${...}" in a Terraform template is the escape for a literal
  # "${...}" - it would emit the expression text, not the list name.
  list_lookup = { for rule in var.rules : rule.list_name => format("http.request.full_uri in $%s", rule.list_name) }

  # Exact hostnames become one `in` set; domains expand to the apex plus anything
  # under it. `ends_with` with a leading dot rather than a wildcard match, so that
  # "notexample.com" cannot satisfy a scope written for "example.com".
  scope_terms = {
    for rule in var.rules : rule.list_name => compact(concat(
      length(rule.scope_hostnames) > 0 ? [
        format("http.host in {%s}", join(" ", [for hostname in rule.scope_hostnames : "\"${lower(hostname)}\""]))
      ] : [],
      [
        for domain in rule.scope_domains :
        format("http.host eq \"%s\" or ends_with(http.host, \".%s\")", lower(domain), lower(domain))
      ],
    ))
  }

  expressions = {
    for rule in var.rules : rule.list_name => (
      length(local.scope_terms[rule.list_name]) == 0
      ? local.list_lookup[rule.list_name]
      : format(
        "(%s) and (%s)",
        join(" or ", [for term in local.scope_terms[rule.list_name] : "(${term})"]),
        local.list_lookup[rule.list_name],
      )
    )
  }

  rules = [
    for rule in var.rules : {
      action      = "redirect"
      expression  = local.expressions[rule.list_name]
      description = rule.description != null ? rule.description : "Bulk Redirects - ${rule.list_name}"
      enabled     = rule.enabled
      ref         = rule.ref != null ? rule.ref : rule.list_name

      action_parameters = {
        from_list = {
          name = rule.list_name
          # The whole request URL is the lookup key, which is why a list row's
          # source carries the hostname. Matching on http.request.uri instead
          # would make one row apply to every hostname in the account.
          key = "http.request.full_uri"
        }
      }
    }
  ]

  # Guardrail inputs
  disabled_rules = [for rule in var.rules : rule.list_name if !rule.enabled]
}
