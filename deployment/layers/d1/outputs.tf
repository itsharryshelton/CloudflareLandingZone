output "d1_databases" {
  description = <<-EOT
    Per-database identifiers, keyed by database key. .github/scripts/d1-migrations.sh
    reads this after apply to find each database's migrations directory and ID:

      wrangler d1 migrations apply "$DATABASE_NAME" --remote

    `file_size` and `num_tables` are read at refresh rather than managed, and are
    here because D1's ceiling is 10 GB per database and nothing else in the
    pipeline reports the approach to it.
  EOT
  value = {
    for key, database in module.d1_databases : key => {
      database_id           = database.database_id
      name                  = database.name
      jurisdiction          = database.jurisdiction
      read_replication_mode = database.read_replication_mode
      file_size             = database.file_size
      num_tables            = database.num_tables
    }
  }
}
