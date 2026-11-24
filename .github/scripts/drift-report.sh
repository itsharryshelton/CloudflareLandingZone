#!/usr/bin/env bash

# drift-report.sh - turn a drift-detection.yml run into one rolling GitHub issue.
#
# Reads from the environment:
#   MATRIX                 the pairs that were meant to be planned, as tf-matrix.sh
#                          emits them: [{"account":"account_a","layer":"zones"}, ...]
#   RESULTS_DIR            directory of <account>--<layer>.json results written by
#                          _terraform-run.yml (default drift-results).
#   MANAGE_ISSUE           "true" => open, update or close the issue. Anything else
#                          => job summary only.
#   RUN_URL                link to this run.
#   DRIFT_ISSUE_LABEL      label that marks the issue (default drift-detection).
#   DRIFT_ISSUE_ASSIGNEES  optional, comma-separated GitHub logins to assign.
#   DRIFT_ISSUE_MENTION    optional, e.g. "@yourorg/platform-oncall", written into
#                          the issue and every change comment.
#   GH_TOKEN, GITHUB_REPOSITORY  for gh, when MANAGE_ISSUE is true.
#
# One issue, not one per night: it is opened when drift first appears, gets a
# comment (which notifies) only when the set of drifted resources changes, and is
# closed when a full run comes back clean. A night that finds the same drift as
# the last one edits the body - which notifies nobody - so the issue shows it
# was still there without paging anyone again.
#
# Everything written is a resource address and an action. No attribute values,
# the same rule as the plan summary in _terraform-run.yml - but addresses carry
# for_each keys such as zone names and record keys, so the issue is exactly as
# visible as the repository.

set -euo pipefail

RESULTS_DIR="${RESULTS_DIR:-drift-results}"
LABEL="${DRIFT_ISSUE_LABEL:-drift-detection}"
MANAGE_ISSUE="${MANAGE_ISSUE:-false}"
ASSIGNEES="${DRIFT_ISSUE_ASSIGNEES:-}"
MENTION="${DRIFT_ISSUE_MENTION:-}"
: "${MATRIX:?MATRIX is required}"
: "${RUN_URL:?RUN_URL is required}"

# Per pair and per list. Beyond this the plan artifact has the rest.
MAX_LINES=40
# GitHub rejects an issue body or comment over 65536 characters.
MAX_BODY=60000

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Through a file, never --argjson: a zones layer drifted across a few hundred
# zones is well past the 128 KiB Linux allows a single argument.
if compgen -G "$RESULTS_DIR/*.json" >/dev/null; then
  jq -s -c '.' "$RESULTS_DIR"/*.json >"$tmp/results.json"
else
  echo '[]' >"$tmp/results.json"
fi

# A pair with no result is a plan that did not finish: an expired token, a held
# lock, a zone that does not exist yet. That is a blind spot, so it is reported
# as loudly as drift rather than being taken for clean.
pairs="$(jq -c -n --argjson m "$MATRIX" --slurpfile r "$tmp/results.json" '
  [ $m[] as $p
    | ([$r[0][] | select(.account == $p.account and .layer == $p.layer)] | first) as $x
    | if $x == null then
        {account: $p.account, layer: $p.layer, status: "unchecked", outside: [], planned: []}
      elif (($x.outside | length) + ($x.planned | length)) > 0 then
        $x + {status: "drift"}
      else
        $x + {status: "clean"}
      end
  ] | sort_by(.account, .layer)')"

total=$(jq 'length' <<<"$pairs")
drifted=$(jq '[.[] | select(.status == "drift")] | length' <<<"$pairs")
unchecked=$(jq '[.[] | select(.status == "unchecked")] | length' <<<"$pairs")
clean=$(( total - drifted - unchecked ))
echo "pairs=$total drift=$drifted unchecked=$unchecked clean=$clean"

# The fingerprint covers what needs a human, not when it was seen, so the same
# drift two nights running hashes the same.
fingerprint="$(jq -c '[.[] | select(.status != "clean") | {account, layer, status, outside, planned}]' <<<"$pairs" \
  | sha256sum | cut -c1-16)"

checked_at="$(date -u '+%Y-%m-%d %H:%M UTC')"

title="Cloudflare drift: ${drifted} drifted, ${unchecked} not checked"

render_details() {
  jq -r --argjson max "$MAX_LINES" '
    def lines($list):
      ($list[:$max] | map("- `" + .a + "` " + .r) | join("\n"))
      + (if ($list | length) > $max
         then "\n- _... and \(($list | length) - $max) more, listed in the plan artifact._"
         else "" end);
    .[] | select(.status != "clean")
    | "### `\(.account)` / `\(.layer)`\n\n"
      + (if .status == "unchecked" then
           "The plan did not finish, so this pair was **not checked**. Open the run for the failing job.\n"
         else
           (if (.outside | length) > 0
            then "**Changed outside Terraform** (edited at Cloudflare since the last apply):\n\n" + lines(.outside) + "\n\n"
            else "" end)
           + (if (.planned | length) > 0
              then "**An apply would change** (reverting the above, plus any merged change not yet applied):\n\n" + lines(.planned) + "\n"
              else "" end)
         end)
  ' <<<"$pairs"
}

render_body() { # <with details: true|false>
  local cell
  {
    echo "## Cloudflare is out of step with \`main\`"
    echo
    [[ -n "$MENTION" ]] && { echo "$MENTION"; echo; }
    echo "The nightly read-only plan found **${drifted}** account/layer pair(s) drifted and **${unchecked}** it could not check, out of ${total}."
    echo
    echo "Last checked: ${checked_at}, [run]($RUN_URL)."
    echo
    echo "| Account | Layer | Changed outside Terraform | An apply would change |"
    echo "|---|---|---|---|"
    jq -r '.[] | select(.status != "clean")
      | if .status == "unchecked"
        then "| `\(.account)` | `\(.layer)` | **not checked** | **not checked** |"
        else "| `\(.account)` | `\(.layer)` | \(.outside | length) | \(.planned | length) |"
        end' <<<"$pairs"
    echo
    if [[ "$1" == true ]]; then
      render_details
      echo
    else
      echo "_Resource lists left out to fit GitHub's size limit. Each pair's job summary in the run lists them._"
      echo
    fi
    cat <<'EOF'
### What to do

- **Changed outside Terraform, and it should stay:** put the change into the account's `.tfvars`, merge it, then run Terraform Apply for that pair.
- **Changed outside Terraform, and it should not have been:** run Terraform Apply for that pair. Its plan reverts the change, and waits for approval like any other.
- **Not expected, and in WAF, DNS, Access or Gateway:** treat it as a possible security incident first. Check the Cloudflare audit log for who made it.
- **Only "an apply would change":** code was merged and never applied. Apply it, or revert the merge.
- **Not checked:** read the failing job. Usual causes are an expired plan token, a lock left by a cancelled run (State Unlock) or a zone merged but not yet applied.

Attribute values are not posted here. The full plan for each pair is the `tfplan-<account>-<layer>-*` artifact on the run, kept for 3 days. A clean full run closes this issue.
EOF
    echo
    echo "<!-- drift-fingerprint: ${fingerprint} -->"
  }
}

body="$(render_body true)"
if (( ${#body} > MAX_BODY )); then
  body="$(render_body false)"
fi

# The job summary gets the report every time, whether or not the issue moves.
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  if (( drifted + unchecked == 0 )); then
    echo "### No drift. All ${total} account/layer pairs match \`main\`." >>"$GITHUB_STEP_SUMMARY"
  else
    printf '%s\n' "$body" >>"$GITHUB_STEP_SUMMARY"
  fi
fi

if [[ "$MANAGE_ISSUE" != "true" ]]; then
  echo "Narrowed run: reported to the job summary only, issue left alone."
  exit 0
fi

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required to manage the issue}"
gh_repo=(--repo "$GITHUB_REPOSITORY")

# Create the label if it is missing. A failure here is only a label that
# already exists or cannot be created; the list below fails loudly if it is
# something worse, rather than this run opening a duplicate issue.
gh label create "$LABEL" "${gh_repo[@]}" --color B60205 \
  --description "Opened and closed by drift-detection.yml" >/dev/null 2>&1 || true

open_issues="$(gh issue list "${gh_repo[@]}" --label "$LABEL" --state open \
  --json number,body --limit 20)"
open_count=$(jq 'length' <<<"$open_issues")
if (( open_count > 1 )); then
  echo "::warning::$open_count open issues carry the '$LABEL' label. Updating the oldest; close the others by hand."
fi
number="$(jq -r 'sort_by(.number) | .[0].number // empty' <<<"$open_issues")"
old_fingerprint="$(jq -r 'sort_by(.number) | .[0].body // ""' <<<"$open_issues" \
  | grep -oE 'drift-fingerprint: [0-9a-f]+' | awk '{print $2}' | head -n1 || true)"

printf '%s\n' "$body" >"$tmp/body.md"

if (( drifted + unchecked == 0 )); then
  if [[ -z "$number" ]]; then
    echo "No drift and no open issue. Nothing to do."
    exit 0
  fi
  gh issue close "$number" "${gh_repo[@]}" --reason completed \
    --comment "All ${total} account/layer pairs match \`main\` again as of ${checked_at} ([run]($RUN_URL)). Closing."
  echo "Closed #$number: drift cleared."
  exit 0
fi

if [[ -z "$number" ]]; then
  assignee_args=()
  [[ -n "$ASSIGNEES" ]] && assignee_args=(--assignee "$ASSIGNEES")
  # An assignee who cannot be assigned (no repository access, a typo) fails
  # the whole create. Opening the issue matters more than who it lands on.
  if ! url="$(gh issue create "${gh_repo[@]}" --title "$title" --body-file "$tmp/body.md" \
      --label "$LABEL" "${assignee_args[@]}" 2>"$tmp/err")"; then
    if (( ${#assignee_args[@]} > 0 )); then
      echo "::warning::could not assign '$ASSIGNEES' ($(head -c 300 "$tmp/err")). Opening the issue unassigned."
      url="$(gh issue create "${gh_repo[@]}" --title "$title" --body-file "$tmp/body.md" --label "$LABEL")"
    else
      cat "$tmp/err" >&2
      exit 1
    fi
  fi
  echo "Opened $url"
  exit 0
fi

gh issue edit "$number" "${gh_repo[@]}" --title "$title" --body-file "$tmp/body.md" >/dev/null

if [[ "$fingerprint" == "$old_fingerprint" ]]; then
  echo "Same drift as #$number already reports. Body refreshed, nobody notified."
  exit 0
fi

{
  [[ -n "$MENTION" ]] && { echo "$MENTION"; echo; }
  echo "The drift has changed as of ${checked_at} ([run]($RUN_URL)): now **${drifted}** drifted and **${unchecked}** not checked, out of ${total}. The issue description has the current list."
} >"$tmp/comment.md"
gh issue comment "$number" "${gh_repo[@]}" --body-file "$tmp/comment.md" >/dev/null
echo "Updated #$number: drift changed, comment posted."
