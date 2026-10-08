locals {
  input_names = [
    for record in var.records : trimsuffix(lower(trimspace(record.name)), ".")
  ]

  # Record types whose content is a hostname rather than free text.
  hostname_content_types = ["CNAME", "MX", "NS", "PTR"]

  # Cloudflare's API stores and returns DNS names fully-qualified. Sending a
  # relative name ("www") therefore reads back as "www.example.com" and shows
  # perpetual drift on every plan, so qualify every name up front. "@" is
  # accepted for the apex out of dashboard familiarity.
  records_normalised = [
    for idx, record in var.records : {
      name = (
        contains(["@", var.domain_name], local.input_names[idx])
        ? var.domain_name
        : endswith(local.input_names[idx], ".${var.domain_name}")
        ? local.input_names[idx]
        : "${local.input_names[idx]}.${var.domain_name}"
      )
      type = upper(record.type)
      # Cloudflare rewrites a hostname target on write: "@" becomes the apex and
      # the name is lowercased. Sending it as written therefore reads back
      # different, and the record shows an update on every plan that no apply
      # ever settles. Other types are left alone - TXT content is case-sensitive.
      content = (
        !contains(local.hostname_content_types, upper(record.type))
        ? record.content
        : trimspace(record.content) == "@"
        ? var.domain_name
        : lower(record.content)
      )
      # Content as written, kept only to build the state key from - see
      # records_grouped.
      key_content = record.content
      ttl         = record.ttl
      proxied     = record.proxied
      priority    = record.priority
      comment     = record.comment
      tags        = record.tags
    }
  ]

  # Stable, unique key per record so reordering the input list never forces a
  # replacement. type+name+content is unique for well-formed record sets.
  #
  # The key format is load-bearing beyond this module: it is what the `records`
  # output is keyed on, and therefore what an `import` block in a calling layer
  # addresses. Changing it re-keys every record in state.
  #
  # That is why the key uses the content as written rather than as sent: keying
  # on the normalised content would destroy and recreate every record whose
  # target was written as "@" or in upper case.
  records_grouped = {
    for record in local.records_normalised :
    "${record.type}/${record.name}/${record.key_content}" => record...
  }

  records = {
    for key, records in local.records_grouped : key => records[0]
  }

  duplicate_keys = [
    for key, records in local.records_grouped : key if length(records) > 1
  ]
}