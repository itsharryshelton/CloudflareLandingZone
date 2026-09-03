#!/usr/bin/env bash

# tf-varfiles.sh <layer_dir> <account_dir>
#
# Prints the `-var-file=` arguments a given layer needs for a given account,
# one per line, with paths relative to the LAYER directory (so the caller can
# `cd` into the layer and pass them straight to terraform).
#
#   $ .github/scripts/tf-varfiles.sh deployment/layers/waf deployment/accounts/account_a
#   -var-file=../../accounts/account_a/account.tfvars
#   -var-file=../../accounts/account_a/waf.tfvars
#   -var-file=../../accounts/account_a/zones.tfvars
#

set -euo pipefail

LAYER_DIR="${1:?usage: tf-varfiles.sh <layer_dir> <account_dir>}"
ACCOUNT_DIR="${2:?usage: tf-varfiles.sh <layer_dir> <account_dir>}"

[[ -d "$LAYER_DIR" ]]   || { echo "no such layer directory: $LAYER_DIR" >&2; exit 1; }
[[ -d "$ACCOUNT_DIR" ]] || { echo "no such account directory: $ACCOUNT_DIR" >&2; exit 1; }

# Top-level variable assignments in a tfvars file. Anchored at column 0 so
# nested object keys (which are always indented in this repository) are ignored.
tfvars_assignments() {
  grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=' "$1" 2>/dev/null \
    | sed 's/[[:space:]]*=$//' | LC_ALL=C sort -u
}

layer_declares_var() {
  grep -rhqE "^variable[[:space:]]+\"$2\"[[:space:]]*\{" "$LAYER_DIR"/*.tf 2>/dev/null
}

shopt -s nullglob
for varfile in "$ACCOUNT_DIR"/*.tfvars; do
  # `*.local.tfvars` is an operator's gitignored override and must never be
  # picked up by a pipeline run.
  case "$(basename "$varfile")" in *.local.tfvars) continue ;; esac

  mapfile -t assigned < <(tfvars_assignments "$varfile")
  # A tfvars file that assigns nothing (comments only) is passable everywhere,
  # but passing it buys nothing - skip it so the command line stays readable.
  [[ ${#assigned[@]} -eq 0 ]] && continue

  declared=0
  undeclared=0
  for v in "${assigned[@]}"; do
    if layer_declares_var "$LAYER_DIR" "$v"; then
      declared=$((declared + 1))
    else
      undeclared=$((undeclared + 1))
    fi
  done

  if [[ $undeclared -eq 0 ]]; then
    echo "-var-file=$(realpath --relative-to="$LAYER_DIR" "$varfile")"
  elif [[ $declared -gt 0 ]]; then
    # Partially matching means one file assigns variables owned by two different layers.
    echo "ERROR: $varfile assigns variables from more than one layer." >&2
    echo "       $(basename "$LAYER_DIR") declares $declared of ${#assigned[@]}: ${assigned[*]}" >&2
    echo "       Split it so each file's variables belong to a single layer." >&2
    exit 1
  fi
done
