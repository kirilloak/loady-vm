#!/usr/bin/env bash
# Shared helpers for every ld-* script. Sourced, never executed.
#
# The one thing to understand here is ld_repo: work happens in the primary checkout or in a
# worktree, and every script has to act on whichever one the caller is standing in. Resolving it
# from the current directory is what makes the same command correct in both.

# Where the checkout and its worktrees live. Overridable for testing.
LOADY_REPO="${LOADY_REPO:-$HOME/loady-one}"
LOADY_WORKTREES="${LOADY_WORKTREES:-$HOME/loady-worktrees}"
LOADY_VM_REPO="${LOADY_VM_REPO:-$HOME/loady-vm}"
LOADY_STATE="${LOADY_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/loady-vm}"

# The local SQL Server the compose file starts. AppDbContextDesignFactory reads either a
# --connection argument or this variable; ld-migrate passes it explicitly so the commands behave
# the same in a non-interactive shell.
# shellcheck disable=SC2034  # read by ld-migrate.sh, which sources this file
LOADY_SQL_CONNECTION="${loady_relational_database_connection:-Server=localhost,1433;Database=loady;User Id=sa;Password=Passw0rd!;TrustServerCertificate=True;}"

ld_die() { echo "${LD_PROG:-ld}: $*" >&2; exit 1; }
ld_log() { echo "==> $*"; }
ld_warn() { echo "${LD_PROG:-ld}: $*" >&2; }

ld_need() {
  # ld_need <command>...: fail with one clear line rather than deep inside a pipeline.
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || ld_die "$cmd is not installed"
  done
}

ld_repo() {
  # The loady-one checkout this command applies to: the worktree the caller is standing in, or
  # the primary checkout. A directory inside neither resolves to the primary checkout, which is
  # what makes `ld-reset` from the home directory do the obvious thing.
  local root
  if root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    && [[ -f "$root/backend/Loady.slnx" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  [[ -d "$LOADY_REPO" ]] || ld_die "no loady-one checkout at $LOADY_REPO"
  printf '%s\n' "$LOADY_REPO"
}

ld_vm_repo() {
  # This repository, wherever it is checked out.
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s\n' "$root"
}

ld_compose() {
  # docker compose bound to this repository's file, with the checkout it needs exported. The
  # project directory is this repository so relative paths in the file resolve here; the one file
  # that must come from the checkout (nginx.conf) is named through $LOADY_REPO_DIR.
  local repo
  repo="$(ld_repo)"
  LOADY_REPO_DIR="$repo" docker compose \
    --project-directory "$(ld_vm_repo)/compose" \
    -f "$(ld_vm_repo)/compose/loady-vm.yaml" "$@"
}

ld_wait_for() {
  # ld_wait_for <label> <timeout seconds> <command...>: poll until the command succeeds.
  # Readiness is probed from the host rather than trusted to a container healthcheck, because the
  # Cosmos emulator image carries no tooling to check itself with.
  local label="$1" timeout="$2"
  shift 2
  local waited=0
  printf '    waiting for %s' "$label"
  while ! "$@" >/dev/null 2>&1; do
    if ((waited >= timeout)); then
      printf ' timed out after %ss\n' "$timeout"
      return 1
    fi
    printf '.'
    sleep 5
    waited=$((waited + 5))
  done
  printf ' ready (%ss)\n' "$waited"
}
