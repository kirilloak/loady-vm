#!/usr/bin/env bash
# Read-only Azure DevOps PR lookup: details and comment threads, over curl and the read-only PAT
# (Code: Read only) the bootstrap writes to ~/.config/loady/ado-pat. See docs/manual-secrets.md.
# Nothing here writes to Azure DevOps - see AGENTS.md rule 3.
#
# Usage: ld-pr <pr-id-or-url> [--project <name>] [--repo <name>]

set -euo pipefail

org="https://dev.azure.com/Loady-Logistics"
project="loady"
repo="loady-one"

input="${1:-}"
if [[ -z "$input" ]]; then
  echo "usage: ld-pr <pr-id-or-url> [--project <name>] [--repo <name>]" >&2
  exit 2
fi
shift

while (( $# )); do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    *) echo "ld-pr: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [[ "$input" =~ ^https://dev\.azure\.com/([^/]+)/([^/]+)/_git/([^/]+)/pullrequest/([0-9]+) ]]; then
  org="https://dev.azure.com/${BASH_REMATCH[1]}"
  project="${BASH_REMATCH[2]}"
  repo="${BASH_REMATCH[3]}"
  id="${BASH_REMATCH[4]}"
elif [[ "$input" =~ ^[0-9]+$ ]]; then
  id="$input"
else
  echo "ld-pr: not a PR id or Azure DevOps PR URL: $input" >&2
  exit 2
fi

pat="${AZURE_DEVOPS_PAT:-}"
pat_file="$HOME/.config/loady/ado-pat"
if [[ -z "$pat" && -r "$pat_file" ]]; then
  pat="$(cat "$pat_file")"
fi
if [[ -z "$pat" ]]; then
  echo "ld-pr: no Azure DevOps PAT found (AZURE_DEVOPS_PAT unset, $pat_file missing)." >&2
  echo "       docs/manual-secrets.md says how to register one." >&2
  exit 1
fi

api="$org/$project/_apis/git/repositories/$repo/pullRequests/$id"

pr_json="$(curl -sf -u ":$pat" "$api?api-version=7.1")" \
  || { echo "ld-pr: failed to fetch PR $id from $org/$project/$repo" >&2; exit 1; }

echo "$pr_json" | jq -r '
  "PR \(.pullRequestId): \(.title)",
  "  status: \(.status)  author: \(.createdBy.displayName)",
  "  \(.sourceRefName) -> \(.targetRefName)"
'

echo "---"

threads_json="$(curl -sf -u ":$pat" "$api/threads?api-version=7.1")" \
  || { echo "ld-pr: failed to fetch comment threads for PR $id" >&2; exit 1; }

echo "$threads_json" | jq -r '
  .value[]
  | select(.comments | length > 0)
  | select(.comments[0].commentType != "system")
  | "[\(.status // "unknown")] \(.threadContext.filePath // "general")",
    (.comments[] | "  \(.author.displayName) (\(.publishedDate)): \(.content)"),
    ""
'
