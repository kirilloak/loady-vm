#!/usr/bin/env bash
# Place this repository's files inside a loady-one checkout without the checkout ever showing a
# change (AGENTS.md rule 1).
#
# backend/CLAUDE.md and backend/AGENTS.md become symlinks to agents/backend/CLAUDE.md in this
# repository, so an edit an agent makes through either path lands here, under version control,
# rather than in a team repository the founder does not own. Both names point at one file because
# Claude reads CLAUDE.md and Codex reads AGENTS.md.
#
# backend/.run becomes a symlink to dotfiles/rider/run, which is Rider's run configurations: every
# function host, the frontend in each of its modes, and both seeders. Same reason, and the same
# benefit in reverse — a configuration edited in Rider's UI is written straight into this
# repository's working tree, so there is nothing to sync.
#
# The checkout's own backend/.gitignore already ignores CLAUDE.md, AGENTS.md and .idea, but not
# .run. That is checked here rather than assumed, and anything the checkout does not ignore is
# added to .git/info/exclude, which is local to the checkout and never pushed.
#
# Usage: link-agent-files.sh [checkout]      default: the worktree you are in, else ~/loady-one
set -euo pipefail
LD_PROG=ld-agents
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

REPO="${1:-$(ld_repo)}"
VM_REPO="$(ld_vm_repo)"
AGENT_FILE="$VM_REPO/agents/backend/CLAUDE.md"
RUN_DIR="$VM_REPO/dotfiles/rider/run"

[[ -d "$REPO/.git" || -f "$REPO/.git" ]] || ld_die "not a git checkout: $REPO"
[[ -f "$AGENT_FILE" ]] || ld_die "missing $AGENT_FILE"
[[ -d "$RUN_DIR" ]] || ld_die "missing $RUN_DIR"

link_one() {
  # link_one <source> <destination>: create or refresh one symlink, never clobbering a real file.
  # -n on every ln, so relinking a directory replaces the link instead of creating one inside the
  # directory it currently points at.
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    [[ "$(readlink "$dest")" == "$src" ]] && return 0
    ln -sfn "$src" "$dest"
    echo "    relinked ${dest#"$REPO"/}"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    # A real file here is either a teammate's tracked file or unsaved work of the founder's.
    # Either way it is not this script's to delete.
    ld_warn "${dest#"$REPO"/} exists and is not a symlink; left untouched"
    return 0
  fi
  ln -sn "$src" "$dest"
  echo "    linked ${dest#"$REPO"/}"
}

# Exclusions first, links second. `git check-ignore` refuses a path that lies beyond a symbolic
# link, so asking about backend/.run once it is a link to this repository answers with an error
# rather than with yes or no.
#
# The checkout ignores CLAUDE.md, AGENTS.md and .idea itself, but not .run; whatever it does not
# ignore goes into .git/info/exclude, which is local-only and never pushed. Worktrees share the main
# checkout's exclude file, so one entry covers every one of them.
# --git-common-dir prints a path relative to the repository when the command runs inside it, so
# resolve it against the checkout rather than against the caller's working directory. Getting this
# wrong writes the exclusions into whichever repository the caller happened to be standing in.
common_dir="$(git -C "$REPO" rev-parse --git-common-dir)"
[[ "$common_dir" == /* ]] || common_dir="$REPO/$common_dir"
exclude="$common_dir/info/exclude"
# backend/.run carries no trailing slash: it is a symlink, which git treats as a file, and a
# pattern ending in / matches directories only — the exclusion would silently miss it and the
# checkout would show it as untracked. The other two directories here are real directories.
for path in backend/CLAUDE.md backend/AGENTS.md backend/plans/ backend/.run .idea/; do
  if git -C "$REPO" check-ignore -q "$path" 2>/dev/null; then
    continue
  fi
  mkdir -p "$(dirname "$exclude")"
  entry="/$path"
  grep -qxF "$entry" "$exclude" 2>/dev/null && continue
  echo "$entry" >>"$exclude"
  echo "    excluded $entry (the checkout did not ignore it)"
done

link_one "$AGENT_FILE" "$REPO/backend/CLAUDE.md"
link_one "$AGENT_FILE" "$REPO/backend/AGENTS.md"
link_one "$RUN_DIR" "$REPO/backend/.run"

# The guarantee this script exists to provide, asserted rather than hoped for. Every path it
# creates belongs here: one left out is one nobody notices in `git status` until it is pushed.
dirty="$(git -C "$REPO" status --porcelain -- backend/CLAUDE.md backend/AGENTS.md backend/.run)"
[[ -z "$dirty" ]] || ld_die "the checkout shows files this script placed as changes:
$dirty"

echo "==> agent files and run configurations linked into ${REPO/#"$HOME"/\~}"
