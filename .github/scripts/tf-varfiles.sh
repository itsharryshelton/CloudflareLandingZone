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
# WHY THIS IS DERIVED RATHER THAN A HARDCODED TABLE
# -------------------------------------------------
# deployment/README.md guarantees that no two files in an account tree assign
# the same variable - `zones.tfvars` owns the inventory, `waf.tfvars` owns the
# policies, and so on. That makes the mapping computable: a var file belongs to
# a layer if and only if every top-level variable it assigns is declared by that
# layer. `account.tfvars` (cloudflare_account_id) therefore reaches all three
# layers, `dns.tfvars` (zone_config) reaches only the zones layer.
#
# Consequence: adding a layer or an account tfvars file needs no pipeline edit.
# Terraform rejects a -var-file containing an undeclared variable, so the
# "every variable declared" test is exactly the condition for the file to be
# passable at all.
#
# A file whose variables are split across layers is a configuration error, not
# something to paper over - it is reported and exits non-zero. ci.yml also
# checks that every committed account tfvars is claimed by at least one layer.

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
    # Partially matching means one file assigns variables owned by two different
    # layers. Terraform would reject it for whichever layer does not declare the
    # extras, so the config is unusable - fail loudly rather than silently drop.
    echo "ERROR: $varfile assigns variables from more than one layer." >&2
    echo "       $(basename "$LAYER_DIR") declares $declared of ${#assigned[@]}: ${assigned[*]}" >&2
    echo "       Split it so each file's variables belong to a single layer." >&2
    exit 1
  fi
done
