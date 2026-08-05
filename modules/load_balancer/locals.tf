locals {
  origins = [
    for origin in var.origins : {
      name    = origin.name
      address = origin.address
      enabled = origin.enabled
      weight  = origin.weight
      port    = origin.port

      # Only emit the header object when a Host override is supplied, otherwise keep null
      header = origin.header_host == null ? null : { host = origin.header_host }
    }
  ]

  origin_names = [for origin in var.origins : origin.name]
}
