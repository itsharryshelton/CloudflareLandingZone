variable "account_id" {
  type        = string
  description = "Cloudflare Account ID. D1 databases are account-scoped, and a database is reachable from any Worker in the account that binds it."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account identifier."
  }
}

variable "name" {
  type        = string
  description = <<-EOT
    Database name, as it appears in the dashboard and as `wrangler d1` addresses
    it. Unique within the account.

    Cloudflare identifies a database by UUID, but the name is not editable in
    place: changing it here destroys the database and creates another, and a
    destroyed D1 database takes every row with it. There is no snapshot, no
    recycle bin and no undo, so treat this string as the database's identity and
    rename nothing casually.
  EOT

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$", var.name))
    error_message = "name must be 1-64 characters of letters, numbers, underscores or hyphens, beginning with a letter or a number."
  }
}

variable "primary_location_hint" {
  type        = string
  default     = null
  description = <<-EOT
    Region to place the primary database in: wnam, enam, weur, eeur, apac or oc.
    Null lets Cloudflare choose, which it does based on where the database is
    first written from.

    The primary is where every write is executed, so this is a latency decision
    for the workload that writes rather than for the one that reads - reads can
    be served nearer the visitor by `read_replication_mode`. Cloudflare honours
    the hint at creation only; changing it later does nothing to a database that
    already exists.
  EOT

  validation {
    condition     = var.primary_location_hint == null || contains(["wnam", "enam", "weur", "eeur", "apac", "oc"], coalesce(var.primary_location_hint, "wnam"))
    error_message = "primary_location_hint must be null or one of: wnam, enam, weur, eeur, apac, oc."
  }
}

variable "jurisdiction" {
  type        = string
  default     = null
  description = <<-EOT
    Data residency jurisdiction: eu, fedramp or us. Null places the database
    under no jurisdictional restriction, which is Cloudflare's default.

    Unlike `primary_location_hint` this is a constraint rather than a preference,
    and it is fixed at creation - a database cannot be moved between
    jurisdictions, so getting it wrong means exporting and reloading the data
    into a new one. Set it where a regulation names the requirement, and leave it
    null where the concern is only latency.
  EOT

  validation {
    condition     = var.jurisdiction == null || contains(["eu", "fedramp", "us"], coalesce(var.jurisdiction, "eu"))
    error_message = "jurisdiction must be null or one of: eu, fedramp, us."
  }
}

variable "read_replication_mode" {
  type        = string
  default     = null
  description = <<-EOT
    Read replication: "auto" or "disabled". Null leaves the account default in
    place rather than declaring one.

    On "auto", Cloudflare keeps a read replica in every supported region and
    serves reads from the one nearest the request, at no extra storage or compute
    cost. It changes nothing on its own: a Worker only reaches a replica when it
    uses the D1 Sessions API (`env.DB.withSession()`), and every query outside a
    session still goes to the primary.

    Two things follow from that. A replica is eventually consistent, so a read
    that must see a write made moments earlier belongs in the same session as
    that write. And a replica is a copy of the data in another region - where
    `jurisdiction` is set because a regulation requires it, replication is the
    thing that quietly undoes it.

    Turning it off again takes up to 24 hours to take effect, so this is not a
    switch to flip during an incident.
  EOT

  validation {
    condition     = var.read_replication_mode == null || contains(["auto", "disabled"], coalesce(var.read_replication_mode, "auto"))
    error_message = "read_replication_mode must be null, \"auto\" or \"disabled\"."
  }
}
