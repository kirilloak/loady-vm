#!/usr/bin/env bash
# Worktrees. One branch, one directory, one agent session.
#
# `git worktree add` writes its metadata under .git/worktrees/ and never into the working tree, so
# nothing a teammate pulls changes (AGENTS.md rule 1). Linked worktrees share the main checkout's
# .git/info/exclude, so the exclusions link-agent-files.sh may add cover every worktree at once.
#
# What a worktree does not give you is a second stack: the compose services pin container names and
# host ports, so only the worktree holding the `loadystack` slot can run one. And there is one SQL
# Server and one Cosmos emulator on the machine, so a migration applied in one worktree is live in
# all of them. Migration work belongs in one worktree at a time.
#
# Usage:
#   ld-stream.sh new <branch> [--any]    branch off origin/dev and create the worktree
#   ld-stream.sh list
#   ld-stream.sh remove <branch> [--force]
set -euo pipefail
LD_PROG=ld-stream
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/lib.sh"

ld_need git

PRIMARY="$LOADY_REPO"
BASE="${LOADY_BASE_BRANCH:-dev}"
[[ -d "$PRIMARY/.git" ]] || ld_die "no loady-one checkout at $PRIMARY"

command="${1:-}"
shift || true

valid_name() {
  # Matches what the remote actually contains: LOADY-<digits> with an optional slug, on its own or
  # behind feature/, bugfix/ or chore/. --any is the escape hatch for the rare exception.
  [[ "$1" =~ ^((feature|bugfix|chore)/)?LOADY-[0-9]+([-/][A-Za-z0-9._-]+)?$ ]]
}

case "$command" in
  new)
    branch="${1:-}"
    [[ -n "$branch" ]] || ld_die "usage: ld-stn <branch> [--any]"
    if ! valid_name "$branch" && [[ "${2:-}" != --any ]]; then
      ld_die "'$branch' does not look like a Loady branch.
       Expected LOADY-<number>[-slug], optionally behind feature/, bugfix/ or chore/.
       Pass --any if this one is deliberate."
    fi

    path="$LOADY_WORKTREES/$branch"
    [[ -e "$path" ]] && ld_die "$path already exists"

    ld_log "fetching $BASE"
    git -C "$PRIMARY" fetch --quiet origin "$BASE"

    ld_log "worktree $path"
    mkdir -p "$(dirname "$path")"
    if git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$branch"; then
      # The branch already exists locally: check it out rather than refusing or resetting it.
      git -C "$PRIMARY" worktree add "$path" "$branch"
    else
      git -C "$PRIMARY" worktree add -b "$branch" "$path" "origin/$BASE"
    fi

    # The two things a fresh worktree needs to be usable: the agent instructions, and Rider's
    # port mapping, which lives in a per-project .idea directory and is otherwise rebuilt by hand.
    "$HERE/link-agent-files.sh" "$path"
    "$(ld_vm_repo)/dotfiles/sync.sh" --seed-worktree "$path" || \
      ld_warn "could not seed the Rider files into the worktree; run dotfiles/sync.sh by hand"

    echo
    echo "Worktree ready: $path"
    echo "  cd \"$path\"      (or: ld-st $branch)"
    echo "  the stack runs in one worktree at a time; 'ld-start' will say if another holds it."
    ;;

  list)
    git -C "$PRIMARY" worktree list
    echo
    echo "slot loadystack: $("$HERE/slot.sh" holder loadystack || echo free)"
    ;;

  remove)
    branch="${1:-}"
    force="${2:-}"
    [[ -n "$branch" ]] || ld_die "usage: ld-str <branch> [--force]"
    path="$LOADY_WORKTREES/$branch"
    [[ -d "$path" ]] || ld_die "no worktree at $path"

    if [[ "$force" != --force ]]; then
      # Under rule 2 nothing here ever commits, so a worktree holding uncommitted or unpushed work
      # is the normal state and removing it would destroy the only copy.
      dirty="$(git -C "$path" status --porcelain)"
      unpushed="$(git -C "$path" log --oneline "@{u}.." 2>/dev/null || \
                  git -C "$path" log --oneline "origin/$BASE..HEAD" 2>/dev/null || true)"
      if [[ -n "$dirty$unpushed" ]]; then
        cat >&2 <<EOF
ld-str: '$branch' holds work that exists nowhere else.

uncommitted:
${dirty:-  (none)}

unpushed commits:
${unpushed:-  (none)}

Commit and push it, or pass --force to discard it.
EOF
        exit 1
      fi
    fi

    holder="$("$HERE/slot.sh" holder loadystack || true)"
    [[ "$holder" == "$path" ]] && ld_die "'$branch' is running the stack; 'ld-stop' there first"

    git -C "$PRIMARY" worktree remove ${force:+--force} "$path"
    git -C "$PRIMARY" branch -D "$branch" 2>/dev/null || true
    echo "removed $branch"
    ;;

  *)
    ld_die "usage: ld-stream.sh <new|list|remove>"
    ;;
esac
