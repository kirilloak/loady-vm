#!/usr/bin/env bash
# The `loadystack` slot: one exclusive local resource, because the compose services pin container
# names and host ports and the function hosts bind fixed ports. Two worktrees can build and index
# at the same time all day; only one can run the stack.
#
# `ld-reset` is what claims it. The function hosts are Rider's and are not tracked here, so this is
# an announcement of intent rather than an enforcement of it — but it is the announcement that makes
# a second worktree's `ld-reset` refuse instead of destroying the databases the first one is using.
#
# A refusal names the holder and is an answer, not an obstacle: stop the stack in that worktree, or
# do work that does not need it.
#
# Usage:
#   slot.sh claim <slot> <reason>     take it, or fail naming the holder
#   slot.sh release <slot>            give it up (only if you hold it)
#   slot.sh holder <slot>             print the holder, or nothing
#   slot.sh steal <slot> <reason>     take it from a holder that is gone
set -euo pipefail
LD_PROG=slot
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SLOT_DIR="$LOADY_STATE/slots"
command="${1:-}"
slot="${2:-}"
[[ -n "$command" && -n "$slot" ]] || ld_die "usage: slot.sh <claim|release|holder|steal> <slot> [reason]"
file="$SLOT_DIR/$slot"

# Who "we" are: the worktree the caller is standing in. That is the unit of isolation, so it is
# the unit the slot is keyed on, and it makes the refusal message immediately actionable.
holder_now="$(ld_repo)"

read_field() { [[ -f "$file" ]] && sed -n "s/^$1=//p" "$file" || true; }

case "$command" in
  holder)
    read_field holder
    ;;

  claim)
    reason="${3:-}"
    mkdir -p "$SLOT_DIR"
    existing="$(read_field holder)"
    if [[ -n "$existing" && "$existing" != "$holder_now" ]]; then
      cat >&2 <<EOF
slot: '$slot' is held by ${existing/#"$HOME"/\~}
       since $(read_field since), for: $(read_field reason)

       Stop it there ('ld-reset' is what took it), or work on something that does not
       need the stack. If that worktree is gone, take it with:
           $(ld_vm_repo)/scripts/slot.sh steal $slot "<reason>"
EOF
      exit 1
    fi
    # Re-claiming your own slot is a no-op, so ld-reset is safe to run twice.
    printf 'holder=%s\nsince=%s\nreason=%s\npid=%s\n' \
      "$holder_now" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$reason" "$$" >"$file"
    ;;

  release)
    existing="$(read_field holder)"
    if [[ -n "$existing" && "$existing" != "$holder_now" ]]; then
      ld_die "'$slot' is held by ${existing/#"$HOME"/\~}, not by this worktree"
    fi
    rm -f "$file"
    ;;

  steal)
    mkdir -p "$SLOT_DIR"
    printf 'holder=%s\nsince=%s\nreason=%s\npid=%s\n' \
      "$holder_now" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${3:-stolen}" "$$" >"$file"
    echo "slot: '$slot' taken by ${holder_now/#"$HOME"/\~}"
    ;;

  *)
    ld_die "unknown command '$command'"
    ;;
esac
