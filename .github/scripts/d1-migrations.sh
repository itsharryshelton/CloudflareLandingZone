#!/usr/bin/env bash

# d1-migrations.sh <layer_dir>
#
# Applies the committed SQL migrations to the D1 databases the workers layer has
# just created.
#
#   $ CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... \
#       .github/scripts/d1-migrations.sh deployment/layers/workers
#
# WHY THIS IS NOT TERRAFORM
# -------------------------
# A migration is an ordered, one-way change to data. Terraform reconciles a
# desired state: it has no concept of "0003 ran, 0004 has not", it cannot apply
# two files in order, and a resource removed from configuration is a resource it
# proposes to destroy. Modelling `CREATE TABLE` as a Terraform resource gets you
# a plan that offers to drop a table because somebody deleted a file.
#
# So the layer owns the database and the binding, and the schema is applied here,
# against the database_id the layer outputs. wrangler keeps a `d1_migrations`
# table inside each database recording which files it has run, which is what
# makes a re-run of this script a no-op rather than a second application.
#
# WHERE THE FILES LIVE
# --------------------
#   deployment/layers/workers/migrations/<database_key>/0001_initial_schema.sql
#
# <database_key> is the logical key from `d1_databases` in an account tree - the
# same key a binding uses - so nothing here needs a database name or a UUID, and
# adding a migration is a file rather than an edit to this script.
#
# Migrations sit in the layer rather than in an account tree for the same reason
# Worker source does: it is code, it is reviewed as code, and two accounts
# running the same workload should be running the same schema. An account that
# declares the key gets the migrations; one that does not is untouched.
#
# THE FILE NAMES ARE THE ORDER
# ----------------------------
# wrangler sorts by the number at the front of the name and records the file name
# it applied, so:
#   * A name is permanent. Renaming an applied migration makes wrangler apply it
#     again under its new name, against a database that already has the change.
#   * Editing an applied migration does nothing at all - the name is already in
#     d1_migrations - and leaves the file describing a schema that was never
#     created. Add a migration instead.
#
# WHAT IT DOES TO THE DATABASE
# ----------------------------
# Everything is validated before anything is applied, and each database is
# applied separately so a failure on one does not leave a second half-migrated.
# D1 has no snapshots to roll back to, which is why the destructive-statement
# warning below is worth reading rather than skipping.
#
# Reads from the environment:
#   CLOUDFLARE_API_TOKEN    token holding D1 edit on this account. Required.
#   CLOUDFLARE_ACCOUNT_ID   the account the databases live in. Required.
#   CLOUDFLARE_API_BASE_URL wrangler's API root. The pipeline points this at
#                           cf-api-throttle.py so these calls are paced with the
#                           rest of the run; unset, wrangler goes straight to
#                           Cloudflare.
#   DRY_RUN                 1 = list what would be applied and apply nothing.
#   MIGRATIONS_DIR          directory inside the layer holding the per-database
#                           directories. Defaults to "migrations".

set -euo pipefail

LAYER_DIR="${1:?usage: d1-migrations.sh <layer_dir>}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-migrations}"
DRY_RUN="${DRY_RUN:-0}"

# Pinned so a wrangler major release cannot change flag behaviour under a
# pipeline nobody is watching.
WRANGLER="npx --yes wrangler@4"

# Nothing here needs Cloudflare's usage telemetry, and a CI runner cannot answer
# the prompt that asks about it.
export WRANGLER_SEND_METRICS=false

[[ -d "$LAYER_DIR" ]] || { echo "no such layer directory: $LAYER_DIR" >&2; exit 1; }
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is not set}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID is not set}"

for tool in jq terraform; do
  command -v "$tool" >/dev/null || { echo "$tool is not on PATH" >&2; exit 1; }
done

# wrangler resolves a relative migrations_dir against the directory its config
# file is in, so the generated config has to live in the layer. Removed on the
# way out, including on failure.
cleanup() { rm -f "$LAYER_DIR"/.d1-migrations-*.json; }
trap cleanup EXIT
cleanup

# ---------------------------------------------------------------------------
# Which databases, and which directory feeds each.
# ---------------------------------------------------------------------------
if ! databases_json="$(terraform -chdir="$LAYER_DIR" output -json d1_databases 2>/dev/null)"; then
  echo "$LAYER_DIR has no d1_databases output - nothing to migrate"
  exit 0
fi

if [[ "$(jq -r 'length' <<<"$databases_json")" == "0" ]]; then
  echo "no D1 databases in the layer output - nothing to migrate"
  exit 0
fi

# key<TAB>database_id<TAB>name
mapfile -t rows < <(jq -r 'to_entries[] | [.key, .value.database_id, .value.name] | @tsv' <<<"$databases_json")

declare -a MIGRATE_KEYS=() MIGRATE_IDS=() MIGRATE_NAMES=() MIGRATE_DIRS=()
declare -A DECLARED_KEYS=()

shopt -s nullglob

for row in "${rows[@]}"; do
  IFS=$'\t' read -r db_key db_id db_name <<<"$row"
  DECLARED_KEYS["$db_key"]=1

  dir="$LAYER_DIR/$MIGRATIONS_DIR/$db_key"

  if [[ ! -d "$dir" ]]; then
    echo "::notice::$db_key ($db_name) has no migrations directory at $dir - skipping"
    continue
  fi

  files=("$dir"/*.sql)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "::notice::$db_key ($db_name) has no .sql files in $dir - skipping"
    continue
  fi

  MIGRATE_KEYS+=("$db_key")
  MIGRATE_IDS+=("$db_id")
  MIGRATE_NAMES+=("$db_name")
  MIGRATE_DIRS+=("$dir")
done

# ---------------------------------------------------------------------------
# Validate everything before applying anything.
# ---------------------------------------------------------------------------
problems=0

# A directory named for a database that no longer exists is migrations nobody is
# running. Silent otherwise: the apply goes green having skipped the schema the
# author thought they had shipped.
for dir in "$LAYER_DIR/$MIGRATIONS_DIR"/*/; do
  orphan="$(basename "$dir")"
  if [[ -z "${DECLARED_KEYS[$orphan]:-}" ]]; then
    echo "::error::$MIGRATIONS_DIR/$orphan names no database in this account's d1_databases - its migrations never run. Declared keys: ${!DECLARED_KEYS[*]}"
    problems=$((problems + 1))
  fi
done

for i in "${!MIGRATE_KEYS[@]}"; do
  db_key="${MIGRATE_KEYS[$i]}"
  dir="${MIGRATE_DIRS[$i]}"

  declare -A seen_sequence=()
  count=0
  db_problems=0

  for file in "$dir"/*.sql; do
    name="$(basename "$file")"
    count=$((count + 1))

    # wrangler orders by the leading number and records the whole file name.
    # Four zero-padded digits so `ls` and wrangler agree on the order past
    # migration ten.
    if [[ ! "$name" =~ ^[0-9]{4}_[A-Za-z0-9._-]+\.sql$ ]]; then
      echo "::error::$db_key: $name is not named <0000>_<description>.sql - wrangler orders migrations by that number"
      problems=$((problems + 1))
      db_problems=$((db_problems + 1))
      continue
    fi

    sequence="${name%%_*}"
    if [[ -n "${seen_sequence[$sequence]:-}" ]]; then
      echo "::error::$db_key: $name and ${seen_sequence[$sequence]} share the number $sequence - the order between them is whatever the filesystem says"
      problems=$((problems + 1))
      db_problems=$((db_problems + 1))
    fi
    seen_sequence["$sequence"]="$name"

    # An empty file is recorded as applied and changes nothing, so the number is
    # burned and the migration it was meant to hold has to be written under a
    # different one.
    if [[ ! -s "$file" ]] || ! grep -qE '[^[:space:]]' "$file"; then
      echo "::error::$db_key: $name is empty - wrangler would record it as applied and apply nothing"
      problems=$((problems + 1))
      db_problems=$((db_problems + 1))
    fi
  done

  unset seen_sequence
  if [[ $db_problems -eq 0 ]]; then
    echo "ok: $db_key ($count migration file(s) in ${dir#"$LAYER_DIR"/})"
  fi
done

if [[ $problems -gt 0 ]]; then
  echo "::error::$problems migration problem(s) - nothing was applied"
  exit 1
fi

if [[ ${#MIGRATE_KEYS[@]} -eq 0 ]]; then
  echo "no database has migrations - nothing to apply"
  exit 0
fi

# Reported rather than refused: dropping a column is a legitimate migration, and
# the decision belongs in the pull request that adds the file. D1 has no
# snapshot to restore from, so it is worth saying out loud in the run that this
# is what is about to happen.
for i in "${!MIGRATE_KEYS[@]}"; do
  db_key="${MIGRATE_KEYS[$i]}"
  destructive="$(grep -rniE '(DROP[[:space:]]+(TABLE|INDEX|VIEW|COLUMN)|TRUNCATE|DELETE[[:space:]]+FROM)' \
    "${MIGRATE_DIRS[$i]}" --include='*.sql' || true)"
  if [[ -n "$destructive" ]]; then
    echo "::warning::$db_key has migrations that remove data. D1 cannot be rolled back:"
    sed 's|^.*/||; s/^/  /' <<<"$destructive"
  fi
done

# ---------------------------------------------------------------------------
# Apply.
# ---------------------------------------------------------------------------
verb="applying"
[[ "$DRY_RUN" == "1" ]] && verb="listing (DRY RUN, nothing will be applied)"
echo "$verb migrations for ${#MIGRATE_KEYS[@]} database(s)"

for i in "${!MIGRATE_KEYS[@]}"; do
  db_key="${MIGRATE_KEYS[$i]}"
  db_id="${MIGRATE_IDS[$i]}"
  db_name="${MIGRATE_NAMES[$i]}"

  # wrangler will only run migrations for a database its configuration file
  # declares, so the configuration is generated from what Terraform just
  # applied rather than committed - a committed database_id would be a second
  # copy of a value the state already owns, and the first one to go stale.
  config="$LAYER_DIR/.d1-migrations-$db_key.json"
  jq -n \
    --arg name "d1-migrations-$db_key" \
    --arg database_name "$db_name" \
    --arg database_id "$db_id" \
    --arg migrations_dir "$MIGRATIONS_DIR/$db_key" \
    '{
      name: $name,
      d1_databases: [
        {
          binding: "DB",
          database_name: $database_name,
          database_id: $database_id,
          migrations_dir: $migrations_dir
        }
      ]
    }' >"$config"

  echo "::group::$db_key ($db_name)"

  # Addressed by name rather than by ID because that is what wrangler matches
  # against database_name in the configuration above; the ID is what makes sure
  # the name resolves to the database this layer created rather than to another
  # one that happens to share it.
  if [[ "$DRY_RUN" == "1" ]]; then
    $WRANGLER d1 migrations list "$db_name" --config "$config" --remote
  else
    $WRANGLER d1 migrations apply "$db_name" --config "$config" --remote
  fi

  echo "::endgroup::"

  rm -f "$config"
done

echo "D1 migrations complete for ${#MIGRATE_KEYS[@]} database(s)"
