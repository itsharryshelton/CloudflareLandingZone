# `migrations` - D1 schema, one directory per database

```
migrations/
  <database_key>/
    0001_initial_schema.sql
    0002_add_kind_index.sql
```

`<database_key>` is the logical key from `d1_databases` in an account tree - the
same key a `d1` binding uses - so nothing here carries a database name or a UUID.
After every successful `workers` apply,
[`d1-migrations.sh`](../../../../.github/scripts/d1-migrations.sh) reads the
`d1_databases` output, finds the directory matching each key and applies whatever
has not run yet. A database with no directory here is skipped; a directory naming
no database fails the run rather than being quietly ignored.

Migrations live in the layer rather than in an account tree for the same reason
Worker source does: they are code, they are reviewed as code, and two accounts
running the same workload should be running the same schema. Because this
directory is shared by every account, an account with no D1 databases at all is
untouched, but an account that declares any D1 database must declare every key
that has a directory here, or its run fails before anything is applied.

## Why not Terraform

Terraform reconciles a desired state. It has no concept of "0003 ran and 0004 has
not", it cannot apply two files in order, and a resource removed from
configuration is one it proposes to destroy - so `CREATE TABLE` as a Terraform
resource is a plan that eventually offers to drop a table because somebody
deleted a file.

The layer owns the database and the binding. wrangler keeps a `d1_migrations`
table inside each database recording which file names it has run, which is what
makes running the script twice a no-op.

## Naming

`<0000>_<description>.sql`, four zero-padded digits. wrangler orders by that
number and records the file name it applied, so:

- **A name is permanent.** Renaming an applied migration makes wrangler apply it
  again, under its new name, to a database that already has the change.
- **Editing an applied migration does nothing.** The name is already in
  `d1_migrations`, so the edit is never executed and the file now describes a
  schema that was never created. Add another migration instead.
- **Numbers are unique within a directory.** Two files sharing one leaves the
  order between them up to the filesystem, which the script refuses.
- **No empty files.** An empty or whitespace-only file is refused: wrangler would
  record it as applied and apply nothing, using up its number. Only `*.sql` files
  are considered, and four digits cap a directory at 9999 migrations.

## Writing one

Idempotent statements where SQLite offers them (`CREATE TABLE IF NOT EXISTS`,
`CREATE INDEX IF NOT EXISTS`), so a migration that failed halfway - D1 applies a
file as one statement batch, not one transaction - can be re-run.

Treat a migration that drops a table or a column as a one-way door. D1's Time
Travel can restore a database to an earlier point, but that rewinds every write
since, not just the migration. The script prints a warning naming the file rather
than refusing it, because the decision belongs in the pull request that adds it.
It greps every `.sql` file here for `DROP TABLE`, `DROP INDEX`, `DROP VIEW`,
`DROP COLUMN`, `TRUNCATE` and `DELETE FROM`, applied or not, so the warning repeats
on every run for as long as such a file is in the directory.

## Running it by hand

Same script, with `DRY_RUN=1` to list what would be applied without applying it.
It is committed without the executable bit, so call it with `bash`:

```bash
CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... DRY_RUN=1 \
  bash .github/scripts/d1-migrations.sh deployment/layers/workers
```

It needs jq, terraform and npx (wrangler 4 is fetched through npx), and it reads
the database IDs out of the layer's state, so it has to run where that state is
reachable - which in the pipeline is the apply job itself. If the layer is not
initialised against the account's state, the script reports that the layer has no
`d1_databases` output - "nothing to migrate" - and exits 0. Check for that line
before trusting a dry run.
