#!/usr/bin/env bash

# kv-bulk-load.sh <layer_dir>
#
# Loads bulk KV datasets into the namespaces the workers layer has just applied.
#
#   $ CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... \
#       .github/scripts/kv-bulk-load.sh deployment/layers/workers
#
# WHY THIS IS NOT TERRAFORM
# -------------------------
# A dataset - a redirect table, a catalogue - can run to tens of thousands of
# keys. As `pairs` it would be one resource in state per key, one line in every
# plan and one API call on every apply. Terraform owns the namespace, the Worker
# and the binding; the rows are loaded here, against the namespace_id the layer
# outputs. layers/workers/data/kv/README.md draws the same line.
#
# WHY THE FILE NAME IS DERIVED
# ----------------------------
# A dataset file is the namespace title with its environment suffix removed:
#
#   namespace title       dataset file
#   ------------------    ----------------------------
#   redirects-uk-prod  -> data/bulk/redirects-uk.json
#   redirects-uk-dev   -> data/bulk/redirects-uk.json
#
# So prod and dev read the same committed data into separate namespaces, and
# adding a dataset is a tfvars entry plus a file - no table in this script to
# keep in step. A namespace with no matching file is skipped: it is either
# configuration-shaped and owned by Terraform through `pairs_file`, or it is not
# dataset-backed at all.
#
# WHAT IT DOES TO THE NAMESPACE
# -----------------------------
# Upsert first, then delete the keys the file no longer contains. Deleting every
# key and writing them back instead would leave a window where the namespace is
# empty and every read misses. Writing first means a key that exists in both is
# only ever updated in place.

set -euo pipefail

LAYER_DIR="${1:?usage: kv-bulk-load.sh <layer_dir>}"
# Not data/kv: that directory is for pairs_file data Terraform owns.
DATA_DIR="${DATA_DIR:-data/bulk}"

# Cloudflare's KV bulk endpoint takes at most 10,000 pairs per request.
CHUNK_SIZE="${CHUNK_SIZE:-10000}"

# Environment suffixes a namespace title may carry. A title ending in one of
# these is the same dataset in a different environment.
ENV_SUFFIXES='prod|dev|stage|test'

# Pinned so a wrangler major release cannot change flag behaviour under a
# pipeline nobody is watching.
WRANGLER="npx --yes wrangler@4"

[[ -d "$LAYER_DIR" ]] || { echo "no such layer directory: $LAYER_DIR" >&2; exit 1; }
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is not set}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID is not set}"

for tool in jq terraform; do
  command -v "$tool" >/dev/null || { echo "$tool is not on PATH" >&2; exit 1; }
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
# Which namespaces, and which file feeds each.
# ---------------------------------------------------------------------------
namespaces_json="$(terraform -chdir="$LAYER_DIR" output -json kv_namespaces)"

if [[ "$(jq -r 'length' <<<"$namespaces_json")" == "0" ]]; then
  echo "no KV namespaces in the layer output - nothing to load"
  exit 0
fi

# key<TAB>namespace_id<TAB>title
mapfile -t rows < <(jq -r 'to_entries[] | [.key, .value.namespace_id, .value.title] | @tsv' <<<"$namespaces_json")

declare -a LOAD_KEYS=() LOAD_IDS=() LOAD_FILES=()

for row in "${rows[@]}"; do
  IFS=$'\t' read -r ns_key ns_id ns_title <<<"$row"

  dataset="$LAYER_DIR/$DATA_DIR/$(sed -E "s/-($ENV_SUFFIXES)$//" <<<"$ns_title").json"

  if [[ ! -f "$dataset" ]]; then
    echo "::notice::$ns_key ($ns_title) has no dataset at $dataset - skipping"
    continue
  fi

  LOAD_KEYS+=("$ns_key")
  LOAD_IDS+=("$ns_id")
  LOAD_FILES+=("$dataset")
done

if [[ ${#LOAD_KEYS[@]} -eq 0 ]]; then
  echo "no namespace has a dataset file - nothing to load"
  exit 0
fi

# ---------------------------------------------------------------------------
# Validate everything before writing anything.
# ---------------------------------------------------------------------------
# A bulk load bypasses the layer's plan-time duplicate check, which only applies
# to a file passed through `pairs_file`. Each failure checked here is silent in
# production: a duplicate key means the last row quietly wins, and a
# self-referential redirect rule sends the browser back to the page it is
# already on until it gives up.
problems=0
declare -A seen_dataset=()

for i in "${!LOAD_FILES[@]}"; do
  dataset="${LOAD_FILES[$i]}"
  # Prod and dev share a file; validating it twice would just double the output.
  [[ -n "${seen_dataset[$dataset]:-}" ]] && continue
  seen_dataset["$dataset"]=1

  if ! jq -e 'type == "array"' "$dataset" >/dev/null 2>&1; then
    echo "::error::$dataset is not a JSON array in Cloudflare bulk format"
    problems=$((problems + 1))
    continue
  fi

  if ! jq -e 'all(.[]; has("key") and has("value"))' "$dataset" >/dev/null; then
    echo "::error::$dataset has an entry missing \"key\" or \"value\""
    problems=$((problems + 1))
  fi

  duplicates="$(jq -r 'group_by(.key)[] | select(length > 1) | "\(.[0].key) (\(length) times)"' "$dataset")"
  if [[ -n "$duplicates" ]]; then
    echo "::error::$dataset repeats a key - the last one silently wins:"
    sed 's/^/  /' <<<"$duplicates"
    problems=$((problems + 1))
  fi

  # "/a" -> "/a;301" sends the browser back to where it already is.
  loops="$(jq -r '.[] | select((.value | split(";")[0]) == .key) | .key' "$dataset")"
  if [[ -n "$loops" ]]; then
    echo "::error::$dataset has rules that redirect a path to itself:"
    sed 's/^/  /' <<<"$loops"
    problems=$((problems + 1))
  fi

  echo "ok: $dataset ($(jq -r 'length' "$dataset") keys)"
done

if [[ $problems -gt 0 ]]; then
  echo "::error::$problems dataset problem(s) - nothing was written to KV"
  exit 1
fi

# ---------------------------------------------------------------------------
# Load.
# ---------------------------------------------------------------------------
for i in "${!LOAD_KEYS[@]}"; do
  ns_key="${LOAD_KEYS[$i]}"
  ns_id="${LOAD_IDS[$i]}"
  dataset="${LOAD_FILES[$i]}"
  total="$(jq -r 'length' "$dataset")"

  echo "::group::$ns_key <- $(basename "$dataset") ($total keys)"

  offset=0
  while [[ $offset -lt $total ]]; do
    chunk="$WORK_DIR/chunk.json"
    jq -c ".[$offset:$((offset + CHUNK_SIZE))]" "$dataset" >"$chunk"
    echo "put $offset..$((offset + CHUNK_SIZE > total ? total : offset + CHUNK_SIZE)) of $total"
    $WRANGLER kv bulk put "$chunk" --namespace-id "$ns_id" --remote
    offset=$((offset + CHUNK_SIZE))
  done

  # Keys the dataset no longer lists. Without this a rule deleted from the file
  # stays live in KV forever, and the file stops describing what the Worker does.
  live="$WORK_DIR/live.json"
  stale="$WORK_DIR/stale.json"
  $WRANGLER kv key list --namespace-id "$ns_id" --remote >"$live"

  # Guard rather than trust: if wrangler ever writes a banner to stdout, the jq
  # below would see no keys, conclude nothing is stale and delete nothing. That
  # failure is silent, which is worse than stopping here.
  if ! jq -e 'type == "array"' "$live" >/dev/null 2>&1; then
    echo "::error::wrangler kv key list did not return a JSON array for $ns_key - skipping stale-key removal"
    exit 1
  fi

  # Membership through an object rather than `IN`, which is a linear scan per key
  # and turns a 15,000-key namespace into 225 million comparisons.
  jq -s '.[0] as $live | .[1] as $wanted
         | ($wanted | map({ (.key): true }) | add // {}) as $keep
         | [$live[].name | select($keep[.] | not)]' "$live" "$dataset" >"$stale"

  stale_count="$(jq -r 'length' "$stale")"
  if [[ "$stale_count" -gt 0 ]]; then
    echo "deleting $stale_count key(s) no longer in $(basename "$dataset")"
    $WRANGLER kv bulk delete "$stale" --namespace-id "$ns_id" --remote --force
  else
    echo "no stale keys"
  fi

  echo "::endgroup::"
done

echo "KV bulk load complete for ${#LOAD_KEYS[@]} namespace(s)"
