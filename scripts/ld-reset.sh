#!/usr/bin/env bash
# Recreate the local containers from scratch: what the old `ld-reset` alias did, fixed and moved
# here. Destroys the volumes, so the next ld-start reseeds.
#
# Usage:
#   ld-reset.sh            containers only
#   ld-reset.sh --hard     also dotnet clean and clear the run state
set -euo pipefail
LD_PROG=ld-reset
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/lib.sh"

ld_need docker jq

REPO="$(ld_repo)"
HARD=0
[[ "${1:-}" == --hard ]] && HARD=1

drift_check() {
  # compose/loady-vm.yaml is this repository's own file, so a change the team makes to theirs does
  # not reach it. Compare the two on the things that actually break a local stack — which services
  # exist and which image each one runs — and say so. A warning, not a failure: cosmosdb is here by
  # design and a deliberate difference is the normal case.
  local theirs="$REPO/backend/compose.yaml"
  [[ -f "$theirs" ]] || return 0
  command -v docker >/dev/null || return 0

  local ours_services theirs_services
  ours_services="$(ld_compose config --format json 2>/dev/null \
    | jq -r '.services | to_entries[] | "\(.key)=\(.value.image // "-")"' | sort)" || return 0
  theirs_services="$(docker compose -f "$theirs" --project-directory "$REPO/backend" config --format json 2>/dev/null \
    | jq -r '.services | to_entries[] | "\(.key)=\(.value.image // "-")"' | sort)" || return 0

  local only_theirs
  only_theirs="$(comm -13 <(printf '%s\n' "$ours_services") <(printf '%s\n' "$theirs_services"))"
  if [[ -n "$only_theirs" ]]; then
    ld_warn "compose drift: loady-one/backend/compose.yaml has services this setup does not:
$(printf '%s\n' "$only_theirs" | sed 's/^/         /')
       Reconcile compose/loady-vm.yaml in this repository if the difference is not deliberate."
  fi
}

drift_check

# Stop the function hosts first: they hold connections to the containers being destroyed, and a
# host left running against a wiped database fails in a way that looks like a code problem.
"$HERE/ld-dev.sh" stop >/dev/null 2>&1 || true

"$HERE/slot.sh" claim loadystack "ld-reset in ${REPO/#"$HOME"/\~}"

ld_log "removing containers and volumes"
ld_compose down -v

ld_log "pulling images"
ld_compose pull

ld_log "starting containers"
ld_compose up -d

if ((HARD)); then
  ld_log "dotnet clean"
  dotnet clean "$REPO/backend/Loady.slnx" --nologo --verbosity quiet
  rm -rf "${LOADY_STATE:?}/run"
fi

"$HERE/slot.sh" release loadystack
ld_log "containers recreated. 'ld-start' builds, seeds and starts the function hosts."
