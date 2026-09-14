#!/usr/bin/env bash
# Keep each tracked file here equal to its live counterpart on the VM.
#
# Either side may be edited: a file in this repository, or the live file through the app. The
# content each pair was last synced to is remembered, so a change on one side is copied to the
# other and a change on both sides is a conflict that writes nothing and says so.
#
# This runs on the VM only. The Mac's ~/.claude is owned and synced by another repository; a second
# sync managing the same live file would conflict on every edit and the loser would be whichever
# ran last. The VM has no other manager, which is why it is safe here and nowhere else.
#
# The script never runs git. A change that lands in this repository is a working-tree change for
# the founder to commit (AGENTS.md rule 2).
#
# Usage:
#   sync.sh                        sync every pair
#   sync.sh --check                report a standing conflict, write nothing
#   sync.sh install                install the cron trigger (VM only)
#   sync.sh --seed-worktree <dir>  put the Rider files into a new worktree
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# Manifest paths are relative to this directory, not to the repository root.
DOTFILES_DIR="${DOTFILES_DIR:-$REPO_ROOT/dotfiles}"
HOME_DIR="${DOTFILES_HOME:-$HOME}"
STATE="${DOTFILES_STATE:-${XDG_STATE_HOME:-$HOME_DIR/.local/state}/loady-vm/dotfiles}"
LOADY_REPO="${LOADY_REPO:-$HOME_DIR/loady-one}"

# Rider writes the project files into .idea/.idea.<SolutionName>/.idea/ beside the solution it
# opened, which for backend/Loady.slnx is .idea.Loady. Confirm it on the first Gateway connection
# and correct this one line if Rider chose another name.
RIDER_DIR="backend/.idea/.idea.Loady/.idea"

# Each entry is "<file in this repository>|<live file>". A live path starting with repo: resolves
# inside the loady-one checkout; anything else resolves from the home directory.
MANIFEST=(
  "ai/instructions.md|.claude/CLAUDE.md"
  "ai/instructions.md|.codex/AGENTS.md"
  "ai/claude/settings.json|.claude/settings.json"
  "ai/codex/config.toml|.codex/config.toml"
  "rider/forwardedPorts.xml|repo:$RIDER_DIR/forwardedPorts.xml"
  "rider/indexLayout.xml|repo:$RIDER_DIR/indexLayout.xml"
)

CONFLICT_FILE="$STATE/CONFLICT"

live_path() {
  local live="$1"
  case "$live" in
    repo:*) printf '%s/%s\n' "$LOADY_REPO" "${live#repo:}" ;;
    *) printf '%s/%s\n' "$HOME_DIR" "$live" ;;
  esac
}

state_path() {
  # One state file per pair. The pair, not the file: ai/instructions.md feeds two live paths and
  # each needs its own memory of what it was last equal to.
  printf '%s/%s\n' "$STATE" "$(printf '%s' "$1" | tr '/' '_')"
}

write_file() {
  # Temp-and-rename, 0600: a reader never sees a half-written file, and nothing here is world
  # readable.
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  local tmp
  tmp="$(mktemp "$(dirname "$dest")/.sync.XXXXXX")"
  cat "$src" >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$dest"
}

same() { cmp -s "$1" "$2"; }

sync_pair() {
  local entry="$1"
  local tracked_rel="${entry%%|*}" live_rel="${entry#*|}"
  local tracked="$DOTFILES_DIR/$tracked_rel"
  local live state
  live="$(live_path "$live_rel")"
  state="$(state_path "$entry")"

  [[ -f "$tracked" ]] || { echo "    missing in repository: $tracked_rel"; return 0; }

  if [[ ! -f "$live" ]]; then
    write_file "$tracked" "$live"
    cp "$tracked" "$state"
    echo "    -> ${live/#"$HOME_DIR"/\~}"
    return 0
  fi

  same "$tracked" "$live" && { cp "$tracked" "$state"; return 0; }

  if [[ ! -f "$state" ]]; then
    # No history for this pair: the more recently written side wins. This happens once, on a
    # fresh VM or a newly added pair.
    if [[ "$live" -nt "$tracked" ]]; then
      cp "$live" "$tracked"
      echo "    <- ${live/#"$HOME_DIR"/\~} (first sync, live was newer)"
    else
      write_file "$tracked" "$live"
      echo "    -> ${live/#"$HOME_DIR"/\~} (first sync)"
    fi
    cp "$tracked" "$state"
    return 0
  fi

  local tracked_changed=0 live_changed=0
  same "$tracked" "$state" || tracked_changed=1
  same "$live" "$state" || live_changed=1

  if ((tracked_changed && live_changed)); then
    mkdir -p "$STATE"
    echo "$tracked_rel <-> ${live/#"$HOME_DIR"/\~}" >>"$CONFLICT_FILE"
    echo "    CONFLICT: $tracked_rel and ${live/#"$HOME_DIR"/\~} both changed; nothing written"
    return 0
  fi

  if ((tracked_changed)); then
    write_file "$tracked" "$live"
    echo "    -> ${live/#"$HOME_DIR"/\~}"
  else
    cp "$live" "$tracked"
    echo "    <- ${live/#"$HOME_DIR"/\~}"
  fi
  cp "$tracked" "$state"
}

case "${1:-sync}" in
  --check)
    if [[ -s "$CONFLICT_FILE" ]]; then
      echo "dotfiles: unresolved sync conflict:" >&2
      sort -u "$CONFLICT_FILE" | sed 's/^/  /' >&2
      echo "  Copy the side you want over the other; the next sync clears this." >&2
      exit 0
    fi
    exit 0
    ;;

  --seed-worktree)
    # A new worktree has no .idea, so Rider would open it with no port mapping at all. Seed the
    # tracked files; from then on that worktree's copies are its own.
    target="${2:?usage: sync.sh --seed-worktree <worktree>}"
    for file in forwardedPorts.xml indexLayout.xml; do
      [[ -f "$DOTFILES_DIR/rider/$file" ]] || continue
      write_file "$DOTFILES_DIR/rider/$file" "$target/$RIDER_DIR/$file"
    done
    echo "    seeded Rider files into ${target/#"$HOME_DIR"/\~}"
    exit 0
    ;;

  install)
    # The VM's trigger: one crontab line every two minutes, logged to journald. No launchd agent,
    # because nothing here syncs to the Mac.
    line="*/2 * * * * $REPO_ROOT/dotfiles/sync.sh 2>&1 | /usr/bin/logger -t loady-dotfiles"
    current="$(crontab -l 2>/dev/null || true)"
    if ! printf '%s\n' "$current" | grep -qF "$REPO_ROOT/dotfiles/sync.sh"; then
      printf '%s\n%s\n' "$current" "$line" | grep -v '^$' | crontab -
      echo "installed the dotfiles sync crontab entry (journalctl -t loady-dotfiles)"
    else
      echo "dotfiles sync crontab entry already installed"
    fi
    exit 0
    ;;

  sync) ;;
  *) echo "usage: sync.sh [--check|--seed-worktree <dir>|install]" >&2; exit 2 ;;
esac

mkdir -p "$STATE"
rm -f "$CONFLICT_FILE"
echo "==> dotfiles"
for entry in "${MANIFEST[@]}"; do
  sync_pair "$entry"
done
[[ -s "$CONFLICT_FILE" ]] && exit 1
exit 0
