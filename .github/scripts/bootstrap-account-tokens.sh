#!/usr/bin/env bash

# bootstrap-account-tokens.sh - create Cloudflare Account-Owned API Tokens
# for the Cloudflare Landing Zone pipelines, scoped per layer and exported to CSV.
#
# User API access required to run this script:
#   Account API Tokens:Edit (Account API Tokens Write)
#
# Reference:
#   Account-Owned Tokens: https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/
#   Create Account Token API: https://developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/create/
#
# WARNING:
#   The token values will be exported to a CSV file. You must import them into
#   GitHub Environment Secrets (or Azure Key Vault) immediately and securely
#   delete the CSV file. If a token is compromised, rotate it at once.
#
# Reads from the environment (or prompts interactively):
#   CLOUDFLARE_ACCOUNT_ID   Target Cloudflare Account ID (always prompted if unset).
#   CLOUDFLARE_USER_TOKEN   User API Token with Account API Tokens Write permission.
#   CSV_OUTPUT_PATH         Destination path for exported CSV.
#   DRY_RUN                 1 = print planned tokens and policy payloads, touch nothing.
#   ONLY_TOKEN              Restrict creation to a single token name (optional).

# If running script from PowerShell session use:
# $env:CLOUDFLARE_ACCOUNT_ID = "1234"
# $env:CLOUDFLARE_USER_TOKEN = "cfut_12345"
# $env:DRY_RUN = "0"
# & "C:\Program Files\Git\bin\bash.exe" .github/scripts/bootstrap-account-tokens.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Prerequisites and CLI checks
# ---------------------------------------------------------------------------
# Auto-discover jq if not in default PATH (e.g. WinGet, Scoop, Chocolatey on Windows)
if ! command -v jq >/dev/null 2>&1; then
  for candidate in \
    /c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/jq.exe \
    /c/Users/*/AppData/Local/Microsoft/WinGet/Links/jq.exe \
    "$HOME/AppData/Local/Microsoft/WinGet/Packages"/jqlang.jq_*/jq.exe \
    "$HOME/AppData/Local/Microsoft/WinGet/Links/jq.exe" \
    /c/Users/*/scoop/shims/jq.exe \
    /c/ProgramData/chocolatey/bin/jq.exe \
    /usr/local/bin/jq \
    /opt/homebrew/bin/jq; do
    if [[ -f "$candidate" ]]; then
      export PATH="$PATH:$(dirname "$candidate")"
      break
    fi
  done
fi

command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl is required but not installed." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required but not installed or found in PATH. Install via 'winget install jqlang.jq'." >&2; exit 1; }

DRY_RUN="${DRY_RUN:-0}"
ONLY_TOKEN="${ONLY_TOKEN:-all}"

echo "======================================================================"
echo " Cloudflare Landing Zone: Account-Owned API Token Provisioning"
echo "======================================================================"
echo

# ---------------------------------------------------------------------------
# Interactive inputs: Account ID, User Token, CSV Output Path
# ---------------------------------------------------------------------------
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
if [[ -z "$ACCOUNT_ID" ]]; then
  read -r -p "Enter Cloudflare Account ID: " ACCOUNT_ID
  if [[ -z "$ACCOUNT_ID" ]]; then
    echo "[ERROR] Account ID is required and cannot be empty." >&2
    exit 1
  fi
fi

# Basic sanity check on Account ID format (hex string)
if [[ ! "$ACCOUNT_ID" =~ ^[a-fA-F0-9]{32}$ ]]; then
  echo "[WARNING] Account ID '$ACCOUNT_ID' does not match the standard 32-character hexadecimal format." >&2
fi

AUTH_TOKEN="${CLOUDFLARE_USER_TOKEN:-${CLOUDFLARE_API_TOKEN:-}}"
if [[ -z "$AUTH_TOKEN" ]]; then
  read -r -s -p "Enter User API Token (requires 'Account API Tokens Write'): " AUTH_TOKEN
  echo
  if [[ -z "$AUTH_TOKEN" ]]; then
    echo "[ERROR] User API Token is required to authenticate against Cloudflare API." >&2
    exit 1
  fi
fi

CSV_PATH="${CSV_OUTPUT_PATH:-}"
if [[ -z "$CSV_PATH" ]]; then
  default_csv="./cloudflare-account-tokens-${ACCOUNT_ID}.csv"
  read -r -p "Enter destination path for secrets CSV [default: ${default_csv}]: " CSV_PATH
  CSV_PATH="${CSV_PATH:-$default_csv}"
fi

# If CSV_PATH is an existing directory or ends with a slash/backslash, append default filename
if [[ -d "$CSV_PATH" || "$CSV_PATH" =~ [/\\]$ ]]; then
  CSV_PATH="${CSV_PATH%/}/cloudflare-account-tokens-${ACCOUNT_ID}.csv"
fi

echo
echo "Configuration Summary:"
echo "  Account ID:     $ACCOUNT_ID"
echo "  CSV Output:     $CSV_PATH"
echo "  Token Filter:   $ONLY_TOKEN"
echo "  Dry Run:        $([[ "$DRY_RUN" == "1" ]] && echo "Enabled (no changes will be made)" || echo "Disabled (tokens will be generated)")"
echo

# Retrieve available permission groups from Cloudflare API
echo "Fetching available permission groups from Cloudflare API..."

API_BASE="https://api.cloudflare.com/client/v4"

# Attempt to list permission groups using the user/tokens endpoint
PERM_GROUPS_RESP="$(curl -sS -X GET "${API_BASE}/user/tokens/permission_groups" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -H "Content-Type: application/json")"

SUCCESS="$(echo "$PERM_GROUPS_RESP" | jq -r '.success // false')"
if [[ "$SUCCESS" != "true" ]]; then
  # Fallback to account-specific endpoint if available
  PERM_GROUPS_RESP="$(curl -sS -X GET "${API_BASE}/accounts/${ACCOUNT_ID}/tokens/permission_groups" \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -H "Content-Type: application/json")"
  SUCCESS="$(echo "$PERM_GROUPS_RESP" | jq -r '.success // false')"
fi

if [[ "$SUCCESS" != "true" ]]; then
  echo "[ERROR] Failed to fetch permission groups from Cloudflare API." >&2
  echo "$PERM_GROUPS_RESP" | jq '.errors' >&2
  exit 1
fi

PERM_GROUPS_JSON="$(echo "$PERM_GROUPS_RESP" | jq '.result')"

# Helper function to look up permission group ID by pattern match
# Supports multiple fallback candidate patterns (separated by pipe '|' or passed as separate arguments)
resolve_perm_id() {
  local scope_type="$1" # "account" or "zone" or "any"
  shift
  local candidates=("$@")
  local match_id=""

  for candidate in "${candidates[@]}"; do
    # Candidate may contain pipe-separated synonyms
    IFS='|' read -ra synonyms <<< "$candidate"
    for pattern in "${synonyms[@]}"; do
      local norm_pattern
      norm_pattern="$(echo "$pattern" | sed -E 's/[:\-_]/ /g; s/\bEdit\b/Write/I; s/ +/ /g; s/^ +| +$//g')"

      # 1. Exact or normalised match
      match_id="$(echo "$PERM_GROUPS_JSON" | jq -r --arg pat "$norm_pattern" --arg orig "$pattern" --arg scope "$scope_type" '
        [
          .[] |
          select(
            if $scope == "account" then ((.scopes // []) | index("com.cloudflare.api.account") != null)
            elif $scope == "zone" then ((.scopes // []) | index("com.cloudflare.api.account.zone") != null)
            else true end
          ) |
          select(
            ((.name | ascii_downcase | gsub("[:\\-_]"; " ") | gsub(" +"; " ")) == ($pat | ascii_downcase)) or
            ((.name | ascii_downcase) == ($orig | ascii_downcase)) or
            ((.name | ascii_downcase) == ($pat | ascii_downcase))
          )
        ] | first | .id // empty
      ')"

      # 2. Contains match if exact not found
      if [[ -z "$match_id" ]]; then
        match_id="$(echo "$PERM_GROUPS_JSON" | jq -r --arg pat "$norm_pattern" --arg scope "$scope_type" '
          [
            .[] |
            select(
              if $scope == "account" then ((.scopes // []) | index("com.cloudflare.api.account") != null)
              elif $scope == "zone" then ((.scopes // []) | index("com.cloudflare.api.account.zone") != null)
              else true end
            ) |
            select(
              (.name | ascii_downcase | gsub("[:\\-_]"; " ")) | contains($pat | ascii_downcase)
            )
          ] | first | .id // empty
        ')"
      fi

      if [[ -n "$match_id" ]]; then
        echo "$match_id"
        return 0
      fi
    done
  done

  echo "[ERROR] Could not resolve permission group ID for: '$1' (scope: ${scope_type:-any})" >&2
  return 1
}

# Helper function to resolve multiple permissions to JSON array of objects
build_perm_array() {
  local scope_type="$1"
  shift
  local ids=()
  for perm_candidate in "$@"; do
    local pid
    pid="$(resolve_perm_id "$scope_type" "$perm_candidate")" || return 1
    ids+=("{\"id\":\"$pid\"}")
  done
  (IFS=,; echo "[${ids[*]}]")
}

# Helpers to find Read permissions by scope
get_account_read_perms() {
  echo "$PERM_GROUPS_JSON" | jq '[ .[] | select(((.scopes // []) | index("com.cloudflare.api.account") != null) and ((.name | endswith("Read")) or (.name | endswith(" Read")))) | {id: .id} ]'
}

get_zone_read_perms() {
  echo "$PERM_GROUPS_JSON" | jq '[ .[] | select(((.scopes // []) | index("com.cloudflare.api.account.zone") != null) and ((.name | endswith("Read")) or (.name | endswith(" Read")))) | {id: .id} ]'
}

# Helper to find all Zero Trust & Access Edit permissions
get_all_zerotrust_write_perms() {
  echo "$PERM_GROUPS_JSON" | jq '[
    .[] | 
    select(
      ((.name | contains("Zero Trust")) or (.name | contains("Access"))) and 
      ((.name | endswith("Write")) or (.name | endswith("Edit")))
    ) | 
    {id: .id}
  ]'
}

# Helper to find Resource Tagging write permissions at one scope ("account" or
# "zone"). Resource Tagging is in beta and its permission groups are not in
# Cloudflare's published list, so they are found by name. "Access: Tags" is
# excluded by name: those are Access application tags, a different feature, and
# a loose match on "Tags" would otherwise hand this token Access write.
get_tagging_write_perms() {
  echo "$PERM_GROUPS_JSON" | jq --arg scope "$1" '[
    .[] |
    select(
      if $scope == "account" then ((.scopes // []) | index("com.cloudflare.api.account") != null)
      else ((.scopes // []) | index("com.cloudflare.api.account.zone") != null) end
    ) |
    select(
      (.name | test("(^| )tag"; "i")) and
      (.name | test("access"; "i") | not) and
      ((.name | endswith("Write")) or (.name | endswith("Edit")))
    ) |
    {id: .id}
  ]'
}

echo "Permission catalogue loaded successfully."
echo

# ---------------------------------------------------------------------------
# Define Token Specifications
# ---------------------------------------------------------------------------
# Resources strings for Account-owned tokens:
#   Account scope:  "com.cloudflare.api.account.<ACCOUNT_ID>": "*"
#   Domains scope:  "com.cloudflare.api.account.zone.*": "*"
ACCOUNT_RESOURCE="com.cloudflare.api.account.${ACCOUNT_ID}"
ZONE_RESOURCE="com.cloudflare.api.account.zone.*"

declare -A TOKEN_SPECS

# 1. terraform-plan: All Read permissions split into Account and Zone policies
PLAN_ACCT_READ_PERMS="$(get_account_read_perms)"
PLAN_ZONE_READ_PERMS="$(get_zone_read_perms)"
TOKEN_SPECS["terraform-plan"]="$(cat <<JSON
{
  "name": "terraform-plan",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $PLAN_ACCT_READ_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    },
    {
      "effect": "allow",
      "permission_groups": $PLAN_ZONE_READ_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    }
  ]
}
JSON
)"

# 2. terraform-accountgovernance-apply
ACCT_GOV_PERMS="$(build_perm_array "account" "Account Settings:Edit|Account Settings Write")"
TOKEN_SPECS["terraform-accountgovernance-apply"]="$(cat <<JSON
{
  "name": "terraform-accountgovernance-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $ACCT_GOV_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    }
  ]
}
JSON
)"

# 3. terraform-gateway-apply
GATEWAY_PERMS="$(build_perm_array "account" "Zero Trust:Edit|Zero Trust Write")"
TOKEN_SPECS["terraform-gateway-apply"]="$(cat <<JSON
{
  "name": "terraform-gateway-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $GATEWAY_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    }
  ]
}
JSON
)"

# 4. terraform-loadbalancing-apply
LB_ZONE_PERMS="$(build_perm_array "zone" \
  "DNS:Read|DNS Read" \
  "Zone:Read|Zone Read" \
  "Zone Load Balancers:Edit|Zone Load Balancers Write|Load Balancing:Edit|Load Balancing Write|Load Balancers Write|Load Balancing")"
LB_ACCT_PERMS="$(build_perm_array "account" \
  "Account Load Balancers:Edit|Account Load Balancers Write|Load Balancers Account Write|Load Balancing: Monitors and Pools Write|Load Balancing Write")"
TOKEN_SPECS["terraform-loadbalancing-apply"]="$(cat <<JSON
{
  "name": "terraform-loadbalancing-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $LB_ZONE_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    },
    {
      "effect": "allow",
      "permission_groups": $LB_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    }
  ]
}
JSON
)"

# 5. terraform-r2-apply
R2_ZONE_PERMS="$(build_perm_array "zone" "DNS:Edit|DNS Write" "Zone:Read|Zone Read")"
R2_ACCT_PERMS="$(build_perm_array "account" \
  "Workers R2 Data Catalog:Edit|Workers R2 Data Catalog Write|R2 Data Catalog Write|Workers R2 Storage Write" \
  "Workers R2 SQL:Edit|Workers R2 SQL Write|R2 SQL Write|Workers R2 Storage Write" \
  "Workers R2 Storage:Edit|Workers R2 Storage Write|R2 Storage Write")"
TOKEN_SPECS["terraform-r2-apply"]="$(cat <<JSON
{
  "name": "terraform-r2-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $R2_ZONE_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    },
    {
      "effect": "allow",
      "permission_groups": $R2_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    }
  ]
}
JSON
)"

# 5b. terraform-dns-apply
DNS_ZONE_PERMS="$(build_perm_array "zone" \
  "DNS:Edit|DNS Write" \
  "Zone:Read|Zone Read")"
TOKEN_SPECS["terraform-dns-apply"]="$(cat <<JSON
{
  "name": "terraform-dns-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $DNS_ZONE_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    }
  ]
}
JSON
)"

# 6. terraform-waf-apply
WAF_ZONE_PERMS="$(build_perm_array "zone" "Zone WAF Rules:Edit|Zone WAF Rules Write|Zone WAF:Edit|Zone WAF Write|WAF:Edit|WAF Write")"
TOKEN_SPECS["terraform-waf-apply"]="$(cat <<JSON
{
  "name": "terraform-waf-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $WAF_ZONE_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    }
  ]
}
JSON
)"

# 7. terraform-wan-apply
WAN_ACCT_PERMS="$(build_perm_array "account" \
  "Magic Firewall:Edit|Magic Firewall Write" \
  "Magic Network Monitoring Config:Edit|Magic Network Monitoring Config Write|Magic Network Monitoring Write" \
  "Magic Transit:Edit|Magic Transit Write" \
  "Magic WAN:Edit|Magic WAN Write")"
TOKEN_SPECS["terraform-wan-apply"]="$(cat <<JSON
{
  "name": "terraform-wan-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $WAN_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    }
  ]
}
JSON
)"

# 8. terraform-workers-apply
WORKERS_ACCT_PERMS="$(build_perm_array "account" \
  "Account Settings:Read|Account Settings Read" \
  "Cloudflare Agents:Edit|CF Agents:Edit|Cloudflare Agents Write|CF Agents Write|Agents Write|Cloudflare Agents Read" \
  "D1:Edit|D1 Write" \
  "Pages:Edit|Pages Write" \
  "Queues:Edit|Queues Write" \
  "Secrets Store:Edit|Secrets Store Write" \
  "Workers CI:Edit|Workers CI Write|Workers CI Read" \
  "Workers Containers:Edit|Workers Containers Write|Workers Containers Read" \
  "Workers KV Storage:Edit|Workers KV Storage Write|Workers KV Write" \
  "Workers Observability:Edit|Workers Observability Write|Workers Observability Read" \
  "Workers R2 Storage:Edit|Workers R2 Storage Write" \
  "Workers Scripts:Edit|Workers Scripts Write" \
  "Workers Tail:Edit|Workers Tail Write|Workers Tail Read|Workers Tail:Read|Workers Tail")"
WORKERS_ZONE_PERMS="$(build_perm_array "zone" "Workers Routes:Edit|Workers Routes Write")"
TOKEN_SPECS["terraform-workers-apply"]="$(cat <<JSON
{
  "name": "terraform-workers-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $WORKERS_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    },
    {
      "effect": "allow",
      "permission_groups": $WORKERS_ZONE_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    }
  ]
}
JSON
)"

# 9. terraform-zerotrust-apply
ZT_ACCT_PERMS="$(get_all_zerotrust_write_perms)"
TOKEN_SPECS["terraform-zerotrust-apply"]="$(cat <<JSON
{
  "name": "terraform-zerotrust-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $ZT_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    }
  ]
}
JSON
)"

# 9b. terraform-tunnels-apply
TUNNELS_ACCT_PERMS="$(build_perm_array "account" \
  "Cloudflare Tunnel:Edit|Cloudflare Tunnel Write|Cloudflare One Connectors Write")"
TUNNELS_ZONE_PERMS="$(build_perm_array "zone" \
  "DNS:Edit|DNS Write" \
  "Zone:Read|Zone Read")"
TOKEN_SPECS["terraform-tunnels-apply"]="$(cat <<JSON
{
  "name": "terraform-tunnels-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $TUNNELS_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    },
    {
      "effect": "allow",
      "permission_groups": $TUNNELS_ZONE_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    }
  ]
}
JSON
)"

# 9c. terraform-logpush-apply
LOGPUSH_ACCT_PERMS="$(build_perm_array "account" \
  "Logs:Edit|Logs Write" \
  "Zero Trust: PII Read|Zero Trust PII Read")"
LOGPUSH_ZONE_PERMS="$(build_perm_array "zone" \
  "Logs:Edit|Logs Write" \
  "Zone:Read|Zone Read")"
TOKEN_SPECS["terraform-logpush-apply"]="$(cat <<JSON
{
  "name": "terraform-logpush-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $LOGPUSH_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    },
    {
      "effect": "allow",
      "permission_groups": $LOGPUSH_ZONE_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    }
  ]
}
JSON
)"

# 9d. terraform-deviceposture-apply
# Zero Trust Write is the only grant that reaches posture rules and service
# provider integrations - the same one the gateway token holds.
DEVICE_POSTURE_ACCT_PERMS="$(build_perm_array "account" "Zero Trust:Edit|Zero Trust Write")"
TOKEN_SPECS["terraform-deviceposture-apply"]="$(cat <<JSON
{
  "name": "terraform-deviceposture-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $DEVICE_POSTURE_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    }
  ]
}
JSON
)"

# 9e. terraform-originpulls-apply
ORIGIN_PULLS_ZONE_PERMS="$(build_perm_array "zone" \
  "SSL and Certificates:Edit|SSL and Certificates Write" \
  "Zone:Read|Zone Read")"
TOKEN_SPECS["terraform-originpulls-apply"]="$(cat <<JSON
{
  "name": "terraform-originpulls-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $ORIGIN_PULLS_ZONE_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    }
  ]
}
JSON
)"

# 9f. terraform-turnstile-apply
TURNSTILE_ACCT_PERMS="$(build_perm_array "account" "Turnstile:Edit|Turnstile Sites Write|Turnstile Write")"
TOKEN_SPECS["terraform-turnstile-apply"]="$(cat <<JSON
{
  "name": "terraform-turnstile-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $TURNSTILE_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    }
  ]
}
JSON
)"

# 9g. terraform-pages-apply
PAGES_ACCT_PERMS="$(build_perm_array "account" "Cloudflare Pages:Edit|Pages Write|Cloudflare Pages Write")"
PAGES_ZONE_PERMS="$(build_perm_array "zone" \
  "DNS:Edit|DNS Write" \
  "Zone:Read|Zone Read")"
TOKEN_SPECS["terraform-pages-apply"]="$(cat <<JSON
{
  "name": "terraform-pages-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $PAGES_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    },
    {
      "effect": "allow",
      "permission_groups": $PAGES_ZONE_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    }
  ]
}
JSON
)"

# 9h. terraform-aigateway-apply
AI_GATEWAY_ACCT_PERMS="$(build_perm_array "account" "AI Gateway:Edit|AI Gateway Write")"
TOKEN_SPECS["terraform-aigateway-apply"]="$(cat <<JSON
{
  "name": "terraform-aigateway-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $AI_GATEWAY_ACCT_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": "*"
      }
    }
  ]
}
JSON
)"

# 10. terraform-zone-apply
ZONE_PERMS="$(build_perm_array "zone" \
  "DNS:Edit|DNS Write" \
  "Zone:Edit|Zone Write" \
  "Zone DNS Settings:Edit|Zone DNS Settings Write|DNS Settings Write" \
  "Zone Settings:Edit|Zone Settings Write")"
TOKEN_SPECS["terraform-zone-apply"]="$(cat <<JSON
{
  "name": "terraform-zone-apply",
  "policies": [
    {
      "effect": "allow",
      "permission_groups": $ZONE_PERMS,
      "resources": {
        "$ACCOUNT_RESOURCE": {
          "$ZONE_RESOURCE": "*"
        }
      }
    }
  ]
}
JSON
)"

# 11. terraform-tags-apply
TAGS_ACCT_PERMS="$(get_tagging_write_perms account)"
TAGS_ZONE_PERMS="$(get_tagging_write_perms zone)"
if [[ "$(jq 'length' <<<"$TAGS_ACCT_PERMS")" -eq 0 ]]; then
  echo "[WARNING] No Resource Tagging write permission group in the catalogue - terraform-tags-apply cannot be provisioned. Check the group names under Account API Tokens in the dashboard." >&2
  TOKEN_SPECS["terraform-tags-apply"]=""
else
  if [[ "$(jq 'length' <<<"$TAGS_ZONE_PERMS")" -eq 0 ]]; then
    echo "[WARNING] No zone-scoped Resource Tagging write group found - terraform-tags-apply will be account-scoped only, and tagging zones may be refused." >&2
  fi
  TOKEN_SPECS["terraform-tags-apply"]="$(jq -n --argjson acct "$TAGS_ACCT_PERMS" --argjson zone "$TAGS_ZONE_PERMS" --arg account "$ACCOUNT_RESOURCE" --arg zones "$ZONE_RESOURCE" '{
    name: "terraform-tags-apply",
    policies: (
      [{effect: "allow", permission_groups: $acct, resources: {($account): "*"}}]
      + (if ($zone | length) > 0
         then [{effect: "allow", permission_groups: $zone, resources: {($account): {($zones): "*"}}}]
         else [] end)
    )
  }')"
fi

# Execution & Token Generation
TOKEN_NAMES=(
  "terraform-plan"
  "terraform-accountgovernance-apply"
  "terraform-aigateway-apply"
  "terraform-deviceposture-apply"
  "terraform-dns-apply"
  "terraform-gateway-apply"
  "terraform-loadbalancing-apply"
  "terraform-logpush-apply"
  "terraform-originpulls-apply"
  "terraform-pages-apply"
  "terraform-r2-apply"
  "terraform-tags-apply"
  "terraform-tunnels-apply"
  "terraform-turnstile-apply"
  "terraform-waf-apply"
  "terraform-wan-apply"
  "terraform-workers-apply"
  "terraform-zerotrust-apply"
  "terraform-zone-apply"
)

if [[ "$ONLY_TOKEN" != "all" ]]; then
  # By name rather than by spec: terraform-tags-apply is a real token whose spec
  # can be empty, and that is reported when it is provisioned, not as a typo.
  known=false
  for t in "${TOKEN_NAMES[@]}"; do
    if [[ "$t" == "$ONLY_TOKEN" ]]; then known=true; fi
  done
  if [[ "$known" != true ]]; then
    echo "[ERROR] Unknown token name '$ONLY_TOKEN'. Valid token names are:" >&2
    for t in "${TOKEN_NAMES[@]}"; do echo "  - $t" >&2; done
    exit 1
  fi
  TARGET_TOKENS=("$ONLY_TOKEN")
else
  TARGET_TOKENS=("${TOKEN_NAMES[@]}")
fi

echo "Tokens to provision:"
for t in "${TARGET_TOKENS[@]}"; do
  echo "  - $t"
done
echo

if [[ "$DRY_RUN" == "1" ]]; then
  echo "--- DRY RUN DETAILS ---"
  for t in "${TARGET_TOKENS[@]}"; do
    echo "[$t Payload]:"
    if [[ -z "${TOKEN_SPECS[$t]}" ]]; then
      echo "  (none - no matching permission group in the catalogue, see the warning above)"
    else
      echo "${TOKEN_SPECS[$t]}" | jq .
    fi
    echo
  done
  echo "Dry run complete. No tokens were created and no CSV file was written."
  exit 0
fi

# Prepare CSV output file with restricted permissions
mkdir -p "$(dirname "$CSV_PATH")"
touch "$CSV_PATH"
chmod 600 "$CSV_PATH"
echo "Token Name,Token ID,Token Value,Scope,Created At" > "$CSV_PATH"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
CREATED_COUNT=0
FAILED_COUNT=0

for token_name in "${TARGET_TOKENS[@]}"; do
  payload="${TOKEN_SPECS[$token_name]}"
  echo -n "Provisioning token: ${token_name}... "

  if [[ -z "$payload" ]]; then
    echo "SKIPPED"
    echo "[ERROR] ${token_name} has no permission groups to grant - see the warning printed when the catalogue was loaded." >&2
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi

  # Dispatch POST /accounts/{account_id}/tokens
  RESPONSE="$(curl -sS -X POST "${API_BASE}/accounts/${ACCOUNT_ID}/tokens" \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$payload")"

  REQ_SUCCESS="$(echo "$RESPONSE" | jq -r '.success // false')"

  if [[ "$REQ_SUCCESS" == "true" ]]; then
    TOKEN_ID="$(echo "$RESPONSE" | jq -r '.result.id')"
    TOKEN_VALUE="$(echo "$RESPONSE" | jq -r '.result.value')"
    
    # Identify token scope summary for documentation
    SCOPE_SUMMARY="Account: ${ACCOUNT_ID}"
    
    # Append to CSV
    echo "\"${token_name}\",\"${TOKEN_ID}\",\"${TOKEN_VALUE}\",\"${SCOPE_SUMMARY}\",\"${TIMESTAMP}\"" >> "$CSV_PATH"
    echo "SUCCESS (ID: ${TOKEN_ID})"
    CREATED_COUNT=$((CREATED_COUNT + 1))
  else
    echo "FAILED"
    echo "[ERROR] API response for ${token_name}:" >&2
    echo "$RESPONSE" | jq '.errors' >&2
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done

echo
echo "======================================================================"
echo " Provisioning Summary"
echo "======================================================================"
echo "Tokens Created: $CREATED_COUNT"
echo "Tokens Failed:  $FAILED_COUNT"
echo "CSV Export:     $CSV_PATH"
echo

cat <<EOF
SECURITY WARNING & NEXT STEPS:
1. Token secrets have been saved to: $CSV_PATH
   Permissions on this file have been set to 0600 (owner read/write only).

2. Upload each token into its corresponding GitHub Environment Secret:
   (Replace <account_name> with your target account directory name in deployment/accounts/)

   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-plan
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-account_governance-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-ai_gateway-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-device_posture-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-dns-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-gateway-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-load_balancing-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-logpush-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-origin_pulls-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-pages-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-r2-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-tags-apply   (terraform-tags-apply)
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-tunnels-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-turnstile-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-waf-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-wan-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-workers-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-zerotrust-apply
   gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo> --env <account_name>-zones-apply

3. IMPORTANT: Once imported into GitHub Secrets, PERMANENTLY
   DELETE the CSV file. If any token is exposed, rotate it immediately in the
   Cloudflare Dashboard or via the API.

4. Delete the API Token used to run this script after use, as it has access to manage all tokens created.
EOF
