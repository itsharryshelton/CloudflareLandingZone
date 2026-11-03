# Account: account_a - D1 database inventory. Consumed by the d1 layer, which
# creates the databases, and by the workers layer, which resolves a binding's
# d1_database_key to a database by name.
#
#   terraform -chdir=layers/d1 plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/d1.tfvars \
#     -var-file=../../accounts/account_a/tags.tfvars
#
# Assign d1_databases here and nothing else. A file reaches a layer only when
# that layer declares every variable in it, so a d1-only setting such as
# allow_replicated_d1_in_jurisdiction would stop this file reaching the workers
# layer. Override one of those in a file of its own.
#
# Terraform owns the database. Its schema comes from
# layers/d1/migrations/<key>/ - so this database's tables are in
# migrations/telemetry/ - applied after every d1 apply by
# .github/scripts/d1-migrations.sh. A database that already exists under the
# name given here is adopted rather than created again.
#
# Keys are identity: renaming one destroys the database and every row in it.

d1_databases = {
  telemetry = {
    name                  = "account-a-telemetry"
    primary_location_hint = "weur"
  }
}
