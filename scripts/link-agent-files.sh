#!/usr/bin/env bash
# Place the Loady agent instruction files inside a loady-one checkout without the checkout ever
# showing a change (AGENTS.md rule 1).
#
# backend/CLAUDE.md and backend/AGENTS.md become symlinks to agents/backend/CLAUDE.md in this
# repository, so an edit an agent makes through either path lands here, under version control,
# rather than in a team repository the founder does not own. Both names point at one file because
# Claude reads CLAUDE.md and Codex reads AGENTS.md.
#
# Nothing needs adding to .git/info/exclude: loady-one's own backend/.gitignore already ignores
# CLAUDE.md, AGENTS.md and .idea. That is checked here rather than assumed, and the exclude entry
# is added only if the checkout stops ignoring them.
#
# Usage: link-agent-files.sh [checkout]      default: the worktree you are in, else ~/loady-one
set -euo pipefail
LD_PROG=ld-agents
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

REPO="${1:-$(ld_repo)}"
VM_REPO="$(ld_vm_repo)"
SOURCE="$VM_REPO/agents/backend/CLAUDE.md"

[[ -d "$REPO/.git" || -f "$REPO/.git" ]] || ld_die "not a git checkout: $REPO"
[[ -f "$SOURCE" ]] || ld_die "missing $SOURCE"

link_one() {
  # link_one <destination>: create or refresh one symlink, never clobbering a real file.
  local dest="$1"
  if [[ -L "$dest" ]]; then
    [[ "$(readlink "$dest")" == "$SOURCE" ]] && return 0
    ln -sfn "$SOURCE" "$dest"
    echo "    relinked ${dest#"$REPO"/}"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    # A real file here is either a teammate's tracked file or unsaved work of the founder's.
    # Either way it is not this script's to delete.
    ld_warn "${dest#"$REPO"/} exists and is not a symlink; left untouched"
    return 0
  fi
  ln -s "$SOURCE" "$dest"
  echo "    linked ${dest#"$REPO"/}"
}

link_one "$REPO/backend/CLAUDE.md"
link_one "$REPO/backend/AGENTS.md"

# The checkout must not show these. It ignores them today; if that ever changes, fall back to
# .git/info/exclude, which is local-only and never pushed. Worktrees share the main checkout's
# exclude file, so one entry covers every one of them.
# --git-common-dir prints a path relative to the repository when the command runs inside it, so
# resolve it against the checkout rather than against the caller's working directory. Getting this
# wrong writes the exclusions into whichever repository the caller happened to be standing in.
common_dir="$(git -C "$REPO" rev-parse --git-common-dir)"
[[ "$common_dir" == /* ]] || common_dir="$REPO/$common_dir"
exclude="$common_dir/info/exclude"
for path in backend/CLAUDE.md backend/AGENTS.md backend/plans/ .idea/; do
  if git -C "$REPO" check-ignore -q "$path" 2>/dev/null; then
    continue
  fi
  mkdir -p "$(dirname "$exclude")"
  entry="/$path"
  grep -qxF "$entry" "$exclude" 2>/dev/null && continue
  echo "$entry" >>"$exclude"
  echo "    excluded $entry (the checkout did not ignore it)"
done

# The guarantee this script exists to provide, asserted rather than hoped for.
dirty="$(git -C "$REPO" status --porcelain -- backend/CLAUDE.md backend/AGENTS.md)"
[[ -z "$dirty" ]] || ld_die "the checkout shows the agent files as changes:
$dirty"

echo "==> agent files linked into ${REPO/#"$HOME"/\~}"
