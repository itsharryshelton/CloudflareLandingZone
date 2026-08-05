#!/usr/bin/env bash

# tf-matrix.sh - work out which {account, layer} pairs a change actually affects.
#
# Reads from the environment:
#   BASE_SHA      commit to diff from. Empty => treat everything as affected.
#   HEAD_SHA      commit to diff to (default HEAD).
#   FORCE_ALL     "true" => every pair, ignore the diff.
#   ONLY_ACCOUNT  account name, or "all".
#   ONLY_LAYER    layer name, or "all".
#
# Writes to $GITHUB_OUTPUT (and stdout):
#   matrix       [{"account":"account_a","layer":"zones"}, ...]
#   by_layer     {"zones":["account_a"],"waf":[],"load_balancing":[]}
#   apply_order  [["zones"],["load_balancing","waf"]]
#   tier_count   number of tiers in apply_order
#   tier0        the subset of `matrix` whose layer is in tier 0
#   tier1        the subset of `matrix` whose layer is in tier 1
#   tier0_any    "true" | "false" - whether tier0 is non-empty
#   tier1_any    "true" | "false"
#   any          "true" | "false"
#
# `matrix` drives plan.yml (one job per pair, all in parallel).
#
# `by_layer` + `apply_order` drive apply.yml. Layer directories are NOT numbered,
# so order is never taken from their names - alphabetically "zones" sorts last,
# which is the opposite of what is required. It is derived from the Terraform
# source instead: a layer that CREATES zones (calls modules/zone_base) must apply
# before any layer that only LOOKS ONE UP (data "cloudflare_zone"), because that
# data source fails at plan time until the zone exists.
#
# apply_order is a list of tiers. Walk tiers in order; everything inside one tier
# is independent and may run concurrently. That is strictly better than a linear
# walk - waf and load_balancing depend on zones but not on each other.
#
# The account and layer lists are discovered from the directory tree, and every
# mapping below is derived from the Terraform source, so adding an account, a
# layer or a module needs no edit here. See tf-varfiles.sh for the same argument
# applied to var files.

set -euo pipefail

LAYERS_DIR="deployment/layers"
ACCOUNTS_DIR="deployment/accounts"

BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-HEAD}"
FORCE_ALL="${FORCE_ALL:-false}"
ONLY_ACCOUNT="${ONLY_ACCOUNT:-all}"
ONLY_LAYER="${ONLY_LAYER:-all}"

list_subdirs() { find "$1" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort; }

mapfile -t ALL_LAYERS   < <(list_subdirs "$LAYERS_DIR")
mapfile -t ALL_ACCOUNTS < <(list_subdirs "$ACCOUNTS_DIR")

[[ ${#ALL_LAYERS[@]}   -gt 0 ]] || { echo "no layers found under $LAYERS_DIR" >&2; exit 1; }
[[ ${#ALL_ACCOUNTS[@]} -gt 0 ]] || { echo "no accounts found under $ACCOUNTS_DIR" >&2; exit 1; }


# Apply the operator's explicit narrowing (workflow_dispatch inputs).
in_list() { local n="$1"; shift; local i; for i in "$@"; do [[ "$i" == "$n" ]] && return 0; done; return 1; }

# Validated in the parent shell on purpose. Doing it inside the process
# substitution below would only exit the subshell, so a typo'd input would
# silently select nothing and the run would go green having done nothing.
validate_choice() { # <wanted> <label> <candidates...>
  local wanted="$1" label="$2"; shift 2
  [[ "$wanted" == "all" ]] && return 0
  in_list "$wanted" "$@" && return 0
  echo "::error::unknown $label '$wanted'. Valid values: all $*" >&2
  return 1
}
validate_choice "$ONLY_LAYER"   layer   "${ALL_LAYERS[@]}"
validate_choice "$ONLY_ACCOUNT" account "${ALL_ACCOUNTS[@]}"

select_from() { # <wanted> <label> <candidates...> - pre-validated above
  local wanted="$1"; shift 1
  if [[ "$wanted" == "all" ]]; then printf '%s\n' "$@"; else echo "$wanted"; fi
}

mapfile -t LAYERS   < <(select_from "$ONLY_LAYER"   "${ALL_LAYERS[@]}")
mapfile -t ACCOUNTS < <(select_from "$ONLY_ACCOUNT" "${ALL_ACCOUNTS[@]}")

# Predicates read straight out of the Terraform source.

# Does <layer> call <module>? Matches both the active relative source
# (".../modules/waf") and the commented pinned git source ("//modules/waf?ref=").
layer_uses_module() {
  grep -rhqE "modules/${2}[\"?]" "$LAYERS_DIR/$1"/*.tf 2>/dev/null
}

layer_declares_var() {
  grep -rhqE "^variable[[:space:]]+\"$2\"[[:space:]]*\{" "$LAYERS_DIR/$1"/*.tf 2>/dev/null
}

# Does <layer> create zones, i.e. call the zone_base module? Such a layer must
# apply before any layer that resolves a zone by lookup.
layer_creates_zones() {
  grep -rhqE 'modules/zone_base["?]' "$LAYERS_DIR/$1"/*.tf 2>/dev/null
}

# Does <layer> resolve a zone with a data source rather than creating it? That
# read fails at plan time until the zone exists, which is the whole dependency.
layer_looks_up_zones() {
  grep -rhqE '^[[:space:]]*data[[:space:]]+"cloudflare_zone"' "$LAYERS_DIR/$1"/*.tf 2>/dev/null
}

tfvars_assignments() {
  grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=' "$1" 2>/dev/null \
    | sed 's/[[:space:]]*=$//' | LC_ALL=C sort -u
}

# Accumulate affected pairs.
# Assigned empty explicitly: under `set -u`, a declared-but-never-assigned
# associative array counts as unbound, so `${#PAIRS[@]}` would abort the script
# on the "nothing changed" path.
declare -A PAIRS=()

add_pair() {
  in_list "$1" "${ACCOUNTS[@]}" || return 0
  in_list "$2" "${LAYERS[@]}"   || return 0
  PAIRS["$1|$2"]=1
}
add_layer_everywhere() { local a; for a in "${ACCOUNTS[@]}"; do add_pair "$a" "$1"; done; }
add_account_everywhere() { local l; for l in "${LAYERS[@]}"; do add_pair "$1" "$l"; done; }
add_everything() { local a; for a in "${ACCOUNTS[@]}"; do add_account_everywhere "$a"; done; }

REASONS=()
note() { REASONS+=("$1"); }

if [[ "$FORCE_ALL" == "true" ]]; then
  note "FORCE_ALL set - selecting every account x layer pair."
  add_everything
elif [[ -z "${CHANGED_FILES:-}" ]] && { [[ -z "$BASE_SHA" ]] || ! git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null; }; then
  # No usable base (first push to a branch, force push, or a manual run without
  # one). Fail safe by planning everything rather than silently planning nothing.
  note "No usable base commit ('${BASE_SHA:-none}') - selecting every pair."
  add_everything
else
  if [[ -n "${CHANGED_FILES:-}" ]]; then
    # Explicit file list, newline separated. Used by ci.yml to self-test this
    # mapping without needing two commits to diff.
    mapfile -t CHANGED <<<"$CHANGED_FILES"
    note "Changed files supplied explicitly: ${#CHANGED[@]}"
  else
    mapfile -t CHANGED < <(git diff --name-only "$BASE_SHA" "$HEAD_SHA" -- || true)
    note "Changed files between ${BASE_SHA:0:8} and ${HEAD_SHA:0:8}: ${#CHANGED[@]}"
  fi

  for f in "${CHANGED[@]}"; do
    case "$f" in
      # Pipeline definitions and the lint config affect how every pair is
      # evaluated, so a change to them re-plans the fleet.
      .github/workflows/*|.github/scripts/*|.tflint.hcl|.gitignore)
        note "$f -> global (pipeline/lint config)"
        add_everything
        ;;

      "$LAYERS_DIR"/*)
        layer="$(cut -d/ -f3 <<<"$f")"
        if in_list "$layer" "${ALL_LAYERS[@]}"; then
          note "$f -> layer $layer, all accounts"
          add_layer_everywhere "$layer"
        fi
        ;;

      modules/*)
        mod="$(cut -d/ -f2 <<<"$f")"
        # _TEMPLATE is scaffolding; no layer calls it.
        [[ "$mod" == "_TEMPLATE" ]] && continue
        for layer in "${ALL_LAYERS[@]}"; do
          if layer_uses_module "$layer" "$mod"; then
            note "$f -> module $mod is called by $layer, all accounts"
            add_layer_everywhere "$layer"
          fi
        done
        ;;

      "$ACCOUNTS_DIR"/*.tfvars|"$ACCOUNTS_DIR"/*/*.tfvars)
        account="$(cut -d/ -f3 <<<"$f")"
        in_list "$account" "${ALL_ACCOUNTS[@]}" || continue
        case "$(basename "$f")" in *.local.tfvars) continue ;; esac

        if [[ ! -f "$f" ]]; then
          # Deleted at HEAD: we cannot read which variables it owned, so treat
          # the whole account as affected.
          note "$f -> deleted, selecting all layers for $account"
          add_account_everywhere "$account"
          continue
        fi

        mapfile -t assigned < <(tfvars_assignments "$f")
        if [[ ${#assigned[@]} -eq 0 ]]; then
          note "$f -> comments only, selecting all layers for $account"
          add_account_everywhere "$account"
          continue
        fi
        for layer in "${ALL_LAYERS[@]}"; do
          all_declared=true
          for v in "${assigned[@]}"; do
            layer_declares_var "$layer" "$v" || { all_declared=false; break; }
          done
          if [[ "$all_declared" == true ]]; then
            note "$f -> $layer / $account (declares: ${assigned[*]})"
            add_pair "$account" "$layer"
          fi
        done
        ;;

      *)
        # Docs, READMEs, anything outside the Terraform tree: no infrastructure
        # impact, so nothing is planned for it.
        ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# Emit.
# ---------------------------------------------------------------------------
if [[ ${#PAIRS[@]} -eq 0 ]]; then
  matrix='[]'
else
  matrix="$(printf '%s\n' "${!PAIRS[@]}" | LC_ALL=C sort \
    | jq -R -c 'split("|") | {account: .[0], layer: .[1]}' | jq -s -c '.')"
fi

layers_json="$(printf '%s\n' "${ALL_LAYERS[@]}" | jq -R -c '.' | jq -s -c '.')"
by_layer="$(jq -c -n --argjson m "$matrix" --argjson ls "$layers_json" \
  'reduce $ls[] as $l ({}; .[$l] = [$m[] | select(.layer == $l) | .account])')"

# ---------------------------------------------------------------------------
# Apply order, derived from the source rather than from directory names.
# ---------------------------------------------------------------------------
# Tier 0: layers with no upstream dependency - they create zones, or touch no
#         zone at all.
# Tier 1: layers that resolve a zone through a data source, so they cannot plan
#         until a tier-0 layer has created it.
#
# A layer that both creates and looks up zones is tier 0: it satisfies its own
# dependency within one state.
TIER0=(); TIER1=()
for layer in "${ALL_LAYERS[@]}"; do
  if layer_creates_zones "$layer"; then
    TIER0+=("$layer")
  elif layer_looks_up_zones "$layer"; then
    TIER1+=("$layer")
  else
    TIER0+=("$layer")
  fi
done

if [[ ${#TIER1[@]} -gt 0 && ${#TIER0[@]} -eq 0 ]]; then
  echo "ERROR: layers resolve a zone by lookup (${TIER1[*]}) but no layer creates one." >&2
  echo "       Expected exactly one layer to call modules/zone_base." >&2
  exit 1
fi

tier_json() { # <items...> -> JSON array, empty-safe
  [[ $# -eq 0 ]] && { echo '[]'; return; }
  printf '%s\n' "$@" | LC_ALL=C sort | jq -R -c '.' | jq -s -c '.'
}
apply_order="$(jq -c -n \
  --argjson t0 "$(tier_json "${TIER0[@]}")" \
  --argjson t1 "$(tier_json "${TIER1[@]}")" \
  '[$t0, $t1] | map(select(length > 0))')"

any=true
[[ "$matrix" == "[]" ]] && any=false

# A GitHub Actions job graph is static YAML: a workflow cannot grow a new
# sequential stage at runtime, so apply.yml declares one plan+apply stage pair
# per tier and consumes tier0/tier1 below. tier_count exists so apply.yml can
# fail loudly if the derived dependency graph ever grows deeper than the stages
# it defines, instead of silently never applying the extra tier.
tier_matrix() { # <tier layers...> -> pairs from $matrix whose layer is in the tier
  jq -c -n --argjson m "$matrix" --argjson ls "$(tier_json "$@")" \
    '[$m[] | select(.layer as $l | $ls | index($l))]'
}
tier0="$(tier_matrix "${TIER0[@]}")"
tier1="$(tier_matrix "${TIER1[@]}")"
tier_count="$(jq -r 'length' <<<"$apply_order")"

emit_bool() { [[ "$1" == "[]" ]] && echo false || echo true; }

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "matrix=$matrix"
    echo "by_layer=$by_layer"
    echo "apply_order=$apply_order"
    echo "tier_count=$tier_count"
    echo "tier0=$tier0"
    echo "tier1=$tier1"
    echo "tier0_any=$(emit_bool "$tier0")"
    echo "tier1_any=$(emit_bool "$tier1")"
    echo "any=$any"
  } >>"$GITHUB_OUTPUT"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Selected account x layer pairs"
    echo
    if [[ "$any" == false ]]; then
      echo "_None - no Terraform-affecting files changed._"
    else
      echo "| Account | Layer |"
      echo "|---|---|"
      jq -r '.[] | "| \(.account) | \(.layer) |"' <<<"$matrix"
    fi
    echo
    echo "Apply order (tiers run in sequence, layers within a tier in parallel):"
    echo
    jq -r 'to_entries[] | "\(.key + 1). \(.value | join(", "))"' <<<"$apply_order"
    echo
    echo "<details><summary>How this was decided</summary>"
    echo
    printf '%s\n' "${REASONS[@]}" | sed 's/^/- /'
    echo
    echo "</details>"
  } >>"$GITHUB_STEP_SUMMARY"
fi

printf '%s\n' "${REASONS[@]}" >&2
echo "matrix=$matrix"
echo "by_layer=$by_layer"
echo "apply_order=$apply_order"
echo "tier_count=$tier_count"
echo "tier0=$tier0"
echo "tier1=$tier1"
echo "any=$any"
