output "database_id" {
  value       = coalesce(cloudflare_d1_database.this.uuid, cloudflare_d1_database.this.id)
  description = "Opaque database identifier. This is what a Worker's d1 binding points at, and what `wrangler d1 migrations apply --remote` takes."
}

output "name" {
  value       = cloudflare_d1_database.this.name
  description = "Database name as Cloudflare holds it. Also how `wrangler d1 execute` addresses the database."
}

output "jurisdiction" {
  value       = cloudflare_d1_database.this.jurisdiction
  description = "Data residency jurisdiction the database was created under, or null where it is unrestricted. Fixed at creation - a database cannot be moved between jurisdictions."
}

output "read_replication_mode" {
  value       = try(cloudflare_d1_database.this.read_replication.mode, null)
  description = "Whether Cloudflare keeps read replicas for this database. \"auto\" only changes where a query runs when the Worker uses the D1 Sessions API; anything else still reads from the primary."
}

output "version" {
  value       = cloudflare_d1_database.this.version
  description = "D1 backend version serving the database. \"production\" is the current engine; older databases can still report the earlier one, which is worth knowing before blaming a query plan."
}

output "created_at" {
  value       = cloudflare_d1_database.this.created_at
  description = "When the database was created."
}

output "file_size" {
  value       = cloudflare_d1_database.this.file_size
  description = "Database size in bytes as of the last refresh. Point-in-time rather than a managed value - it is here because D1's per-database ceiling is 10 GB and nothing else in the pipeline reports the approach to it."
}

output "num_tables" {
  value       = cloudflare_d1_database.this.num_tables
  description = "How many tables the database holds as of the last refresh. Zero on a database Terraform has just created, because the schema is applied by a migration step rather than from here."
}
