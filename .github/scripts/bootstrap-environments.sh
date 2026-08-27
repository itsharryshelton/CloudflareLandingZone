#!/usr/bin/env bash

# bootstrap-environments.sh - create the GitHub Environments the apply pipeline
# expects, with required reviewers and a main-only deployment branch policy.
#
# First-time setup, and re-run whenever a layer or an account is added. Run it by
# hand; nothing in the pipelines calls it, because a workflow that can create its
# own approval gates is not an approval gate..
#
# Environment names are DERIVED by the workflows, not free text:
#   <account>-plan           read-only token, no gate. Created by hand, and left
#                            alone here - it must run on PR branches.
#   <account>-<layer>-apply  one per layer, created here, each gated.
#
# Accounts and layers are read out of the working tree for the same reason
# tf-matrix.sh reads them: adding a layer must not need an edit in two places.
# See .github/workflows/README.md for the token scope each environment needs.
#
# Requires gh, authenticated with `repo` scope. Unlike the tf-*.sh scripts in this
# directory it needs no jq: those run on an Ubuntu runner where jq is preinstalled,
# whereas this one is run by hand, often on Windows. gh has jq built in as --jq.
#
# Idempotent - a re-run updates the existing environments in place.
#
# Reads from the environment:
#   REPO                 owner/name. Defaults to the origin remote.
#   REVIEWER_USERS       space-separated usernames. One of these two is required.
#   REVIEWER_TEAMS       space-separated team slugs in the repo's org.
#   PREVENT_SELF_REVIEW  true|false - see below.
#   WAIT_TIMER           minutes before the approval prompt is offered. 0 = at once.
#   DEPLOY_BRANCH        the only branch allowed to deploy. Default main.
#   ONLY_LAYER           restrict to one layer, for adding a single environment.
#   DRY_RUN              1 = print what would change, touch nothing.
#
# This script deliberately does NOT set CLOUDFLARE_API_TOKEN. A token passed as a
# script argument or an exported variable lands in shell history and in terminal
# scrollback, and each environment needs a DIFFERENT one anyway - that is the
# whole point of the layer split. It prints the commands to set them at the end.

set -euo pipefail

REVIEWER_USERS="${REVIEWER_USERS:-}"
REVIEWER_TEAMS="${REVIEWER_TEAMS:-}"

# Whether the person who started an apply may approve it themselves.
#
# true is the control you want, and it needs a second human on the reviewer list
# to be workable - with one name it deadlocks every apply, because there is
# nobody else to click approve. Default true on the assumption of a team; drop it
# to false only for a genuinely single-operator account, and raise it again when
# a second name joins.
PREVENT_SELF_REVIEW="${PREVENT_SELF_REVIEW:-true}"

WAIT_TIMER="${WAIT_TIMER:-0}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
ONLY_LAYER="${ONLY_LAYER:-all}"
DRY_RUN="${DRY_RUN:-0}"

command -v gh >/dev/null || { echo "::error::gh not found - https://cli.github.com/" >&2; exit 1; }

REPO_ROOT="$(git rev-parse --show-toplevel)"
REPO="${REPO:-$(git -C "$REPO_ROOT" remote get-url origin \
  | sed -E 's#(git@github\.com:|https://github\.com/)##; s#\.git$##')}"

# Both are interpolated into a JSON body below, so they are checked rather than
# trusted - a stray value would otherwise produce a confusing API error, or worse
# a body that parses into something other than what was meant.
case "$PREVENT_SELF_REVIEW" in
  true|false) ;;
  *) echo "::error::PREVENT_SELF_REVIEW must be true or false, got '$PREVENT_SELF_REVIEW'" >&2; exit 1 ;;
esac
[[ "$WAIT_TIMER" =~ ^[0-9]+$ ]] || {
  echo "::error::WAIT_TIMER must be a whole number of minutes, got '$WAIT_TIMER'" >&2; exit 1; }

if [[ -z "$REVIEWER_USERS" && -z "$REVIEWER_TEAMS" ]]; then
  # Failing here rather than defaulting: an environment created with no reviewers
  # looks identical in the Actions UI to one with them, and the first anybody
  # would notice is a write token applying unreviewed.
  cat >&2 <<'EOF'
::error::no reviewers given - every apply environment would be created ungated.

  REVIEWER_TEAMS="cf-admins"    bash .github/scripts/bootstrap-environments.sh
  REVIEWER_USERS="alice bob"    bash .github/scripts/bootstrap-environments.sh
EOF
  exit 1
fi

# ---------------------------------------------------------------------------
# Discover accounts and layers from the tree.
# ---------------------------------------------------------------------------
list_subdirs() { find "$1" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort; }

mapfile -t ACCOUNTS < <(list_subdirs "$REPO_ROOT/deployment/accounts")
mapfile -t ALL_LAYERS < <(list_subdirs "$REPO_ROOT/deployment/layers")

[[ ${#ACCOUNTS[@]}   -gt 0 ]] || { echo "::error::no accounts under deployment/accounts" >&2; exit 1; }
[[ ${#ALL_LAYERS[@]} -gt 0 ]] || { echo "::error::no layers under deployment/layers" >&2; exit 1; }

if [[ "$ONLY_LAYER" == "all" ]]; then
  LAYERS=("${ALL_LAYERS[@]}")
else
  # Validated rather than filtered silently: a typo would otherwise create
  # nothing and exit 0, which reads as success.
  printf '%s\n' "${ALL_LAYERS[@]}" | grep -qx "$ONLY_LAYER" || {
    echo "::error::unknown layer '$ONLY_LAYER'. Valid: all ${ALL_LAYERS[*]}" >&2; exit 1; }
  LAYERS=("$ONLY_LAYER")
fi

echo "Repo:     $REPO"
echo "Accounts: ${ACCOUNTS[*]}"
echo "Layers:   ${LAYERS[*]}"
echo "Gate:     reviewers required, ${DEPLOY_BRANCH} only, prevent_self_review=${PREVENT_SELF_REVIEW}"
echo

# ---------------------------------------------------------------------------
# Resolve reviewers to the numeric IDs the API takes.
# ---------------------------------------------------------------------------
ORG="${REPO%%/*}"
REVIEWER_ITEMS=()

for u in $REVIEWER_USERS; do
  id="$(gh api "users/$u" --jq '.id')" || { echo "::error::unknown user '$u'" >&2; exit 1; }
  echo "reviewer: user  $u ($id)"
  REVIEWER_ITEMS+=("{\"type\":\"User\",\"id\":$id}")
done

for t in $REVIEWER_TEAMS; do
  id="$(gh api "orgs/$ORG/teams/$t" --jq '.id')" || { echo "::error::unknown team '$ORG/$t'" >&2; exit 1; }
  members="$(gh api "orgs/$ORG/teams/$t/members" --jq 'length')"
  echo "reviewer: team  $t ($id, $members members)"
  # A one-member team plus prevent_self_review is the deadlock described above,
  # and it only surfaces once somebody has already queued an apply.
  if [[ "$members" -le 1 && "$PREVENT_SELF_REVIEW" == "true" ]]; then
    echo "::warning::team '$t' has $members member(s) and PREVENT_SELF_REVIEW=true." \
         "If that member starts the apply, nobody can approve it."
  fi
  REVIEWER_ITEMS+=("{\"type\":\"Team\",\"id\":$id}")
done
echo

# Only resolved numeric IDs reach the JSON, so plain joining is safe here.
reviewers_csv="$(IFS=,; echo "${REVIEWER_ITEMS[*]}")"

# ---------------------------------------------------------------------------
# Create / update.
# ---------------------------------------------------------------------------
# custom_branch_policies, not protected_branches: "protected" resolves to
# whatever branch protection happens to cover on the day, which is a moving
# target. An explicit allow-list of one branch is not.
body="$(cat <<JSON
{
  "wait_timer": $WAIT_TIMER,
  "prevent_self_review": $PREVENT_SELF_REVIEW,
  "reviewers": [$reviewers_csv],
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
JSON
)"

created=0
updated=0
for account in "${ACCOUNTS[@]}"; do
  for layer in "${LAYERS[@]}"; do
    env_name="${account}-${layer}-apply"

    if gh api "repos/$REPO/environments/$env_name" >/dev/null 2>&1; then
      action=update; updated=$((updated + 1))
    else
      action=create; created=$((created + 1))
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
      printf '%-6s %s\n' "$action" "$env_name"
      continue
    fi

    gh api -X PUT "repos/$REPO/environments/$env_name" \
      -H 'Accept: application/vnd.github+json' \
      --input - <<<"$body" >/dev/null

    # The PUT above only switches custom branch policies ON - it does not populate
    # the list, and an empty list means NO branch may deploy. This call is not
    # optional, and it is a separate collection with no PUT of its own.
    if ! gh api "repos/$REPO/environments/$env_name/deployment-branch-policies" \
           --jq '.branch_policies[].name' 2>/dev/null | grep -qx "$DEPLOY_BRANCH"; then
      gh api -X POST "repos/$REPO/environments/$env_name/deployment-branch-policies" \
        -f "name=$DEPLOY_BRANCH" -f 'type=branch' >/dev/null
    fi

    printf '%-6s %s\n' "$action" "$env_name"
  done
done

echo
echo "$created created, $updated updated."
[[ "$DRY_RUN" == "1" ]] && { echo "(dry run - nothing was changed)"; exit 0; }

cat <<EOF

Each environment still needs its OWN scoped CLOUDFLARE_API_TOKEN - one per layer,
per .github/workflows/README.md. Reusing one across two layers defeats the split.
Set them by typing the value at the prompt, so it stays out of shell history:

$(for account in "${ACCOUNTS[@]}"; do
    for layer in "${LAYERS[@]}"; do
      echo "  gh secret set CLOUDFLARE_API_TOKEN --repo $REPO --env ${account}-${layer}-apply"
    done
  done)

Two layers also take a secret that is not a Cloudflare token, on the same terms:
  zerotrust  TF_VAR_IDENTITY_PROVIDER_SECRETS  {"entra_id":"<client secret>"}
  wan        TF_VAR_WAN_IPSEC_TUNNEL_PSKS      once wan_ipsec_tunnels is populated
EOF
