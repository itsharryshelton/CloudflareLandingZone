locals {
  # Hostnames are compared and stored case-insensitively, so normalise before
  # sending. Order is left exactly as the operator wrote it: Cloudflare stores
  # the list as given, and sorting here would make the stored value differ from
  # the declared one for no gain.
  normalised_domains = {
    for key, widget in var.widgets : key => distinct([
      for domain in widget.domains : lower(trimspace(domain))
    ])
  }

  widgets = {
    for key, widget in var.widgets : key => merge(widget, {
      name    = trimspace(widget.name)
      domains = local.normalised_domains[key]
    })
  }

  # Derived assertions, consumed by the preconditions in main.tf.

  # Cloudflare permits two widgets with the same name. That is a trap at 3am:
  # the dashboard lists both, neither says which site embeds it, and the sitekey
  # is the only thing that distinguishes them.
  duplicate_names = sort([
    for name, claimants in {
      for key, widget in local.widgets : lower(widget.name) => key...
    } : "\"${name}\" (${join(", ", sort(claimants))})" if length(claimants) > 1
  ])

  over_limit = sort([
    for key, domains in local.normalised_domains : "${key} (${length(domains)} hostnames)"
    if length(domains) > var.max_domains_per_widget
  ])

  # A hostname covers its own subdomains, so listing both the apex and a
  # subdomain of it in one widget adds nothing and hides the real coverage from
  # whoever reads the list later.
  redundant_subdomains = sort(flatten([
    for key, domains in local.normalised_domains : [
      for domain in domains : "${key}: ${domain} (already covered by ${[
        for parent in domains : parent if parent != domain && endswith(domain, ".${parent}")
      ][0]})"
      if length([for parent in domains : parent if parent != domain && endswith(domain, ".${parent}")]) > 0
    ]
  ]))

  # Every hostname, with the widget that claims it. Two widgets covering one
  # hostname both work, which is the problem: the page embeds one sitekey, and
  # which one it is cannot be read off this configuration.
  domain_claims = {
    for pair in flatten([
      for key, domains in local.normalised_domains : [
        for domain in domains : { domain = domain, key = key }
      ]
    ]) : pair.domain => pair.key...
  }

  overlapping_domains = sort([
    for domain, claimants in local.domain_claims : "${domain} (${join(", ", sort(claimants))})"
    if length(claimants) > 1
  ])
}
