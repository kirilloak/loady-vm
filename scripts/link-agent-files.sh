#!/usr/bin/env bash
# Place this repository's files inside a loady-one checkout without the checkout ever showing a
# change (AGENTS.md rule 1).
#
# Three directories in the checkout get an instruction file: the root, backend/ and infra/. Each
# gets both names, because Claude reads CLAUDE.md and Codex reads AGENTS.md, and both are symlinks
# to the one AGENTS.md under agents/ in this repository:
#
#   <checkout>/AGENTS.md         -> agents/loady-one/AGENTS.md
#   <checkout>/CLAUDE.md         -> agents/loady-one/AGENTS.md    the same file, the other name
#   <checkout>/backend/AGENTS.md -> agents/backend/AGENTS.md
#   ... and so on for backend and infra
#
# So an edit an agent makes through any of those paths lands here, under version control, rather
# than in a team repository the founder does not own.
#
# CLAUDE.md is not a one-line `@AGENTS.md` import here, though that is the pattern this
# repository's own root uses. Claude follows a symlinked CLAUDE.md wherever it points, but it does
# not follow an `@` import whose target resolves outside the project directory, and every target
# here is in ~/loady-vm. Measured on claude 2.1.272, 2026-09-15; the plan's result file has the
# cases. So the content file is what both names point at.
#
# backend/.run becomes a symlink to dotfiles/rider/run, which is Rider's run configurations: every
# function host, the frontend in each of its modes, and both seeders. Same reason, and the same
# benefit in reverse — a configuration edited in Rider's UI is written straight into this
# repository's working tree, so there is nothing to sync.
#
# Whatever the checkout does not ignore itself is added to .git/info/exclude, which is local to the
# checkout and never pushed. That is checked rather than assumed, per path.
#
# Usage:
#   link-agent-files.sh [checkout]      default: the worktree you are in, else ~/loady-one
#   link-agent-files.sh --all           the primary checkout and every worktree
#   link-agent-files.sh --all --quiet   the same, silent unless something changed or refused
#   link-agent-files.sh install         install the cron trigger (VM only)
set -euo pipefail
LD_PROG=ld-agents
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

VM_REPO="$(ld_vm_repo)"
RUN_DIR="$VM_REPO/dotfiles/rider/run"

# <directory under agents/> | <directory under the checkout>. Adding a fourth project is one line
# here and nothing else.
PROJECTS=(
  "loady-one|."
  "backend|backend"
  "infrastructure|infra"
)

# Directories the checkout must ignore for reasons other than the loop above: Rider's own
# directory, the run configurations, and the plans an agent writes in a worktree.
EXTRA_EXCLUDES=(backend/plans/ backend/.run .idea/)

QUIET=0

ld_say() {
  # Progress, suppressed by --quiet. Changes and warnings do not go through here: cron has to
  # report those.
  ((QUIET)) || echo "$@"
}

ld_rel() {
  # <dir> <name> -> the checkout-relative path, with the root project's "." dropped. "/./AGENTS.md"
  # is not the same exclude pattern as "/AGENTS.md", and git matches the pattern as written.
  local dir="$1" name="$2"
  if [[ "$dir" == "." ]]; then printf '%s\n' "$name"; else printf '%s/%s\n' "$dir" "$name"; fi
}

link_one() {
  # link_one <repo> <source> <destination>: create or refresh one symlink, never clobbering a real
  # file. -n on every ln, so relinking a directory replaces the link instead of creating one inside
  # the directory it currently points at.
  local repo="$1" src="$2" dest="$3"
  if [[ -L "$dest" ]]; then
    [[ "$(readlink "$dest")" == "$src" ]] && return 0
    ln -sfn "$src" "$dest"
    echo "    relinked ${dest#"$repo"/}"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    # A real file here is either a teammate's tracked file or unsaved work of the founder's.
    # Either way it is not this script's to delete.
    ld_warn "${dest#"$repo"/} exists and is not a symlink; left untouched"
    return 0
  fi
  ln -sn "$src" "$dest"
  echo "    linked ${dest#"$repo"/}"
}

exclude_one() {
  # exclude_one <repo> <exclude file> <path>: add one local exclusion, unless the checkout already
  # ignores the path or the entry is already there.
  local repo="$1" exclude="$2" path="$3"
  git -C "$repo" check-ignore -q "$path" 2>/dev/null && return 0
  mkdir -p "$(dirname "$exclude")"
  local entry="/$path"
  grep -qxF "$entry" "$exclude" 2>/dev/null && return 0
  echo "$entry" >>"$exclude"
  echo "    excluded $entry (the checkout did not ignore it)"
}

link_checkout() {
  local repo="$1"
  [[ -d "$repo/.git" || -f "$repo/.git" ]] || ld_die "not a git checkout: $repo"
  [[ -d "$RUN_DIR" ]] || ld_die "missing $RUN_DIR"

  local entry project dir name src rel
  local -a linked=()

  # Exclusions first, links second. `git check-ignore` refuses a path that lies beyond a symbolic
  # link, so asking about backend/.run once it is a link to this repository answers with an error
  # rather than with yes or no.
  #
  # --git-common-dir prints a path relative to the repository when the command runs inside it, so
  # resolve it against the checkout rather than against the caller's working directory. Getting
  # this wrong writes the exclusions into whichever repository the caller happened to be standing
  # in. Worktrees share the main checkout's exclude file, so one entry covers every one of them.
  local common_dir exclude
  common_dir="$(git -C "$repo" rev-parse --git-common-dir)"
  [[ "$common_dir" == /* ]] || common_dir="$repo/$common_dir"
  exclude="$common_dir/info/exclude"

  for entry in "${PROJECTS[@]}"; do
    project="${entry%%|*}"
    dir="${entry#*|}"
    [[ -f "$VM_REPO/agents/$project/AGENTS.md" ]] \
      || ld_die "missing $VM_REPO/agents/$project/AGENTS.md"
    for name in AGENTS.md CLAUDE.md; do
      rel="$(ld_rel "$dir" "$name")"
      linked+=("$rel")
      exclude_one "$repo" "$exclude" "$rel"
    done
  done
  # backend/.run carries no trailing slash: it is a symlink, which git treats as a file, and a
  # pattern ending in / matches directories only — the exclusion would silently miss it and the
  # checkout would show it as untracked. The other two here are real directories.
  for rel in "${EXTRA_EXCLUDES[@]}"; do
    exclude_one "$repo" "$exclude" "$rel"
  done

  for entry in "${PROJECTS[@]}"; do
    project="${entry%%|*}"
    dir="${entry#*|}"
    [[ -d "$repo/$dir" ]] || { ld_warn "${repo}/${dir} does not exist; skipped"; continue; }
    src="$VM_REPO/agents/$project/AGENTS.md"
    for name in AGENTS.md CLAUDE.md; do
      link_one "$repo" "$src" "$repo/$(ld_rel "$dir" "$name")"
    done
  done
  if [[ -d "$repo/backend" ]]; then
    link_one "$repo" "$RUN_DIR" "$repo/backend/.run"
    linked+=(backend/.run)
  fi

  # The guarantee this script exists to provide, asserted rather than hoped for. Every path it
  # creates belongs here: one left out is one nobody notices in `git status` until it is pushed.
  local dirty
  dirty="$(git -C "$repo" status --porcelain -- "${linked[@]}")"
  [[ -z "$dirty" ]] || ld_die "the checkout shows files this script placed as changes:
$dirty"

  ld_say "==> agent files and run configurations linked into ${repo/#"$HOME"/\~}"
}

all_checkouts() {
  # The primary checkout and every worktree beside it. A worktree directory that is not a checkout
  # is skipped rather than fatal: ld-str leaves nothing behind, but a half-removed one should not
  # stop the primary from being linked.
  local path
  [[ -d "$LOADY_REPO/.git" ]] && printf '%s\n' "$LOADY_REPO"
  [[ -d "$LOADY_WORKTREES" ]] || return 0
  for path in "$LOADY_WORKTREES"/*; do
    [[ -d "$path/.git" || -f "$path/.git" ]] || continue
    printf '%s\n' "$path"
  done
}

install_cron() {
  # The VM's trigger: one crontab line a minute, logged to journald. Same shape as the dotfiles
  # sync entry, which is the machine's only other scheduled job.
  local script="$VM_REPO/scripts/link-agent-files.sh"
  local line="* * * * * $script --all --quiet 2>&1 | /usr/bin/logger -t loady-agents"
  local current
  current="$(crontab -l 2>/dev/null || true)"
  if printf '%s\n' "$current" | grep -qF "$script"; then
    echo "agent files crontab entry already installed"
    return 0
  fi
  printf '%s\n%s\n' "$current" "$line" | grep -v '^$' | crontab -
  echo "installed the agent files crontab entry (journalctl -t loady-agents)"
}

if [[ "${1:-}" == install ]]; then
  ld_need crontab
  install_cron
  exit 0
fi

ALL=0
TARGET=""
while (($#)); do
  case "$1" in
    --all) ALL=1 ;;
    --quiet) QUIET=1 ;;
    -*) ld_die "unknown option: $1" ;;
    *) TARGET="$1" ;;
  esac
  shift
done

if ((ALL)); then
  [[ -z "$TARGET" ]] || ld_die "--all takes no checkout argument"
  rc=0
  while read -r repo; do
    # A subshell per checkout, so ld_die in one does not take the rest of them with it.
    ( link_checkout "$repo" ) || rc=1
  done < <(all_checkouts)
  exit "$rc"
fi

link_checkout "${TARGET:-$(ld_repo)}"
