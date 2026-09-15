#!/usr/bin/env bash
# Put this repository's agent instructions inside a loady-one checkout without the checkout ever
# showing a change (AGENTS.md rule 1).
#
# Three directories get a pair of files: the root, backend/ and infra/. AGENTS.md holds the
# instructions, which Codex reads directly; CLAUDE.md is one line, `@AGENTS.md`, which Claude
# follows. Both are real files, copied from agents/ in this repository:
#
#   agents/loady-one/AGENTS.md      <->  <checkout>/AGENTS.md
#   agents/loady-one/CLAUDE.md      <->  <checkout>/CLAUDE.md
#   agents/backend/AGENTS.md        <->  <checkout>/backend/AGENTS.md
#   ... and so on for backend and infra
#
# Real files rather than symlinks, because Claude does not follow an `@` import whose target
# resolves outside the project directory, and the target of a symlink into ~/loady-vm always does.
# Measured on claude 2.1.272; the plan's result file has the cases.
#
# So they are synced instead, the way dotfiles/sync.sh syncs the machine-wide files, and for the
# same reason: either side may be edited. The content each pair was last synced to is remembered
# under ~/.local/state/loady-vm/agents/, so a change on one side is copied to the other and a change
# on both is a conflict that writes nothing and says so. A crontab line runs this every minute over
# the checkout and every worktree.
#
# Nothing here runs git beyond reading (AGENTS.md rule 2). An instruction file edited in a checkout
# lands in this repository's working tree for the founder to commit.
#
# backend/.run gets the same treatment, a directory at a time: dotfiles/rider/run holds Rider's run
# configurations, and Rider rewrites them in the checkout as the founder edits one in its UI. A file
# that appears on either side is copied to the other; a file that had been synced and is now gone on
# one side is deleted from the other. A directory with no sync history is only ever added to.
#
# Whatever the checkout does not ignore itself is added to .git/info/exclude, which is local to the
# checkout and never pushed. That is checked rather than assumed, per path.
#
# Nothing here is a symlink. Every path this script manages is a real file in the checkout, and the
# checkout's .git/info/exclude keeps every one of them out of `git status`.
#
# Usage:
#   sync-agent-files.sh [checkout]      default: the worktree you are in, else ~/loady-one
#   sync-agent-files.sh --all           the primary checkout and every worktree
#   sync-agent-files.sh --all --quiet   the same, silent unless something changed or refused
#   sync-agent-files.sh install         install the cron trigger (VM only)
set -euo pipefail
LD_PROG=ld-agents
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

VM_REPO="$(ld_vm_repo)"
AGENT_STATE="$LOADY_STATE/agents"

# <directory under agents/> | <directory under the checkout>. Adding a fourth project is one line
# here and nothing else.
PROJECTS=(
  "loady-one|."
  "backend|backend"
  "infra|infra"
)

# <directory under this repository> | <directory under the checkout>. Synced file by file rather
# than as a unit: Rider rewrites individual run configurations and creates new ones.
DIR_PAIRS=(
  "dotfiles/rider/run|backend/.run"
)

# Directories the checkout must ignore for reasons other than the two tables above: Rider's own
# directory, and the plans an agent writes in a worktree.
EXTRA_EXCLUDES=(backend/plans/ .idea/)

QUIET=0
CONFLICTS=0

ld_say() {
  # Progress, suppressed by --quiet. Changes and conflicts do not go through here: cron has to
  # report those.
  ((QUIET)) || echo "$@"
}

ld_rel() {
  # <dir> <name> -> the checkout-relative path, with the root project's "." dropped. "/./AGENTS.md"
  # is not the same exclude pattern as "/AGENTS.md", and git matches the pattern as written.
  local dir="$1" name="$2"
  if [[ "$dir" == "." ]]; then printf '%s\n' "$name"; else printf '%s/%s\n' "$dir" "$name"; fi
}

write_file() {
  # Temp-and-rename: a reader never sees a half-written file, and a tool watching the checkout
  # never sees one either.
  local src="$1" dest="$2" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp "$(dirname "$dest")/.ld-agents.XXXXXX")"
  cat "$src" >"$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$dest"
}

state_path() {
  # state_path <checkout> <relative path>: one state file per pair. The pair, not the file: the
  # same AGENTS.md here feeds the checkout and every worktree, and each needs its own memory of
  # what it was last equal to.
  local repo="$1" rel="$2"
  printf '%s/%s/%s\n' "$AGENT_STATE" "$(printf '%s' "${repo#/}" | tr '/' '_')" \
    "$(printf '%s' "$rel" | tr '/' '_')"
}

dir_names() {
  # dir_names <directory>: the regular file names directly inside it, one per line.
  local dir="$1" f
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*; do
    [[ -f "$f" ]] || continue
    printf '%s\n' "${f##*/}"
  done
}

state_names() {
  # state_names <checkout> <relative directory>: the file names this directory has synced before,
  # so a file deleted on both disks is still noticed.
  local repo="$1" rel="$2" prefix f
  prefix="$(state_path "$repo" "$rel")_"
  for f in "$prefix"*; do
    [[ -e "$f" ]] || continue
    printf '%s\n' "${f#"$prefix"}"
  done
}

sync_one() {
  # sync_one <checkout> <file in this repository> <live file> <relative path>
  local repo="$1" tracked="$2" live="$3" rel="$4"
  local state
  state="$(state_path "$repo" "$rel")"
  mkdir -p "$(dirname "$state")"

  # An earlier version of this script linked these paths. A symlink into this repository is this
  # script's own leftover and is replaced with the real file; any other symlink is someone else's.
  if [[ -L "$live" ]]; then
    if [[ "$(readlink "$live")" == "$VM_REPO"/* ]]; then
      rm -f "$live"
    else
      ld_warn "$rel is a symlink this script did not make; left untouched"
      CONFLICTS=1
      return 0
    fi
  fi

  if [[ ! -e "$live" ]]; then
    write_file "$tracked" "$live"
    cp "$tracked" "$state"
    echo "    -> $rel"
    return 0
  fi

  if [[ ! -f "$live" ]]; then
    ld_warn "$rel exists and is not a regular file; left untouched"
    CONFLICTS=1
    return 0
  fi

  cmp -s "$tracked" "$live" && { cp "$tracked" "$state"; return 0; }

  if [[ ! -f "$state" ]]; then
    # No history and the two differ. dotfiles/sync.sh lets the newer side win here; this one must
    # not, because the file it would overwrite may be a teammate's, tracked in a repository the
    # founder does not own.
    ld_warn "$rel differs from ${tracked#"$VM_REPO"/} and has no sync history; nothing written.
       Copy the side you want over the other, then rerun."
    CONFLICTS=1
    return 0
  fi

  local tracked_changed=0 live_changed=0
  cmp -s "$tracked" "$state" || tracked_changed=1
  cmp -s "$live" "$state" || live_changed=1

  if ((tracked_changed && live_changed)); then
    ld_warn "$rel and ${tracked#"$VM_REPO"/} both changed since the last sync; nothing written.
       Copy the side you want over the other; the next run clears this."
    CONFLICTS=1
    return 0
  fi

  if ((tracked_changed)); then
    write_file "$tracked" "$live"
    echo "    -> $rel"
  else
    # The checkout's copy was edited. It goes back into this repository's working tree, which is
    # where the founder commits from.
    write_file "$live" "$tracked"
    echo "    <- $rel"
  fi
  cp "$tracked" "$state"
}

remove_one() {
  # remove_one <path> <state> <label>: the other side deleted a file that had been synced, so this
  # side loses it too. Only ever reached for a pair with sync history.
  local path="$1" state="$2" label="$3"
  rm -f "$path" "$state"
  echo "    x  $label"
}

sync_dir() {
  # sync_dir <checkout> <directory in this repository> <live directory> <relative path>
  local repo="$1" tracked_dir="$2" live_dir="$3" rel="$4"
  local name tracked live state

  # An earlier version of this script linked this directory. Its own link is replaced with a real
  # directory; anything else is left alone and reported.
  if [[ -L "$live_dir" ]]; then
    if [[ "$(readlink "$live_dir")" == "$VM_REPO"/* ]]; then
      rm -f "$live_dir"
    else
      ld_warn "$rel is a symlink this script did not make; left untouched"
      CONFLICTS=1
      return 0
    fi
  fi
  if [[ -e "$live_dir" && ! -d "$live_dir" ]]; then
    ld_warn "$rel exists and is not a directory; left untouched"
    CONFLICTS=1
    return 0
  fi
  mkdir -p "$live_dir"

  # Every name on either side, plus every name that was synced before, so a deletion is visible.
  # Plain globbing rather than find -printf, which is GNU-only and this also runs on the Mac. A
  # leading dot is skipped, which is what keeps a half-written .ld-agents.XXXXXX out of the union;
  # Rider names no run configuration that way.
  local -a names=()
  while read -r name; do [[ -n "$name" ]] && names+=("$name"); done < <(
    {
      dir_names "$tracked_dir"
      dir_names "$live_dir"
      state_names "$repo" "$rel"
    } | sort -u
  )

  for name in "${names[@]}"; do
    tracked="$tracked_dir/$name"
    live="$live_dir/$name"
    state="$(state_path "$repo" "$rel/$name")"
    if [[ -f "$tracked" && ! -e "$live" && -f "$state" ]]; then
      remove_one "$tracked" "$state" "${tracked#"$VM_REPO"/}"
    elif [[ ! -e "$tracked" && -f "$live" && -f "$state" ]]; then
      remove_one "$live" "$state" "$rel/$name"
    elif [[ ! -e "$tracked" && -f "$live" ]]; then
      write_file "$live" "$tracked"
      cp "$live" "$state"
      echo "    <- $rel/$name"
    elif [[ -f "$tracked" ]]; then
      sync_one "$repo" "$tracked" "$live" "$rel/$name"
    fi
  done
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

sync_checkout() {
  local repo="$1"
  [[ -d "$repo/.git" || -f "$repo/.git" ]] || ld_die "not a git checkout: $repo"

  local entry project dir name rel
  local -a managed=()

  # Exclusions first, files second. `git check-ignore` refuses a path that lies beyond a symbolic
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
    for name in AGENTS.md CLAUDE.md; do
      [[ -f "$VM_REPO/agents/$project/$name" ]] \
        || ld_die "missing $VM_REPO/agents/$project/$name"
      rel="$(ld_rel "$dir" "$name")"
      managed+=("$rel")
      exclude_one "$repo" "$exclude" "$rel"
    done
  done
  for entry in "${DIR_PAIRS[@]}"; do
    rel="${entry#*|}"
    managed+=("$rel")
    exclude_one "$repo" "$exclude" "$rel/"
  done
  for rel in "${EXTRA_EXCLUDES[@]}"; do
    exclude_one "$repo" "$exclude" "$rel"
  done

  for entry in "${PROJECTS[@]}"; do
    project="${entry%%|*}"
    dir="${entry#*|}"
    [[ -d "$repo/$dir" ]] || { ld_warn "${repo}/${dir} does not exist; skipped"; continue; }
    for name in AGENTS.md CLAUDE.md; do
      rel="$(ld_rel "$dir" "$name")"
      sync_one "$repo" "$VM_REPO/agents/$project/$name" "$repo/$rel" "$rel"
    done
  done
  for entry in "${DIR_PAIRS[@]}"; do
    project="${entry%%|*}"
    dir="${entry#*|}"
    [[ -d "$repo/$(dirname "$dir")" ]] || continue
    managed+=("$dir")
    sync_dir "$repo" "$VM_REPO/$project" "$repo/$dir" "$dir"
  done

  # The guarantee this script exists to provide, asserted rather than hoped for. Every path it
  # writes belongs here: one left out is one nobody notices in `git status` until it is pushed.
  local dirty
  dirty="$(git -C "$repo" status --porcelain -- "${managed[@]}")"
  [[ -z "$dirty" ]] || ld_die "the checkout shows files this script placed as changes:
$dirty"

  ld_say "==> agent files and run configurations synced into ${repo/#"$HOME"/\~}"
  return "$CONFLICTS"
}

all_checkouts() {
  # The primary checkout and every worktree beside it. A worktree directory that is not a checkout
  # is skipped rather than fatal: ld-str leaves nothing behind, but a half-removed one should not
  # stop the primary from being synced.
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
  local script="$VM_REPO/scripts/sync-agent-files.sh"
  local line="* * * * * $script --all --quiet 2>&1 | /usr/bin/logger -t loady-agents"
  local current kept
  current="$(crontab -l 2>/dev/null || true)"
  if printf '%s\n' "$current" | grep -qxF "$line"; then
    echo "agent files crontab entry already installed"
    return 0
  fi
  # Drop any earlier entry for this job, including the one naming the script by its old
  # link-agent-files.sh name, so a rename leaves one line rather than one working and one failing.
  kept="$(printf '%s\n' "$current" | grep -v 'link-agent-files\.sh\|sync-agent-files\.sh' || true)"
  printf '%s\n%s\n' "$kept" "$line" | grep -v '^$' | crontab -
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
    ( sync_checkout "$repo" ) || rc=1
  done < <(all_checkouts)
  exit "$rc"
fi

sync_checkout "${TARGET:-$(ld_repo)}"
exit "$CONFLICTS"
