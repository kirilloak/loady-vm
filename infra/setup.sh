#!/usr/bin/env bash
# Converge the development VM from the Mac, as often as wanted: runs bootstrap.sh on the VM over
# SSH with the SSH keys from Bitwarden. The VM itself comes from the Terraform root beside this
# file, which runs the same bootstrap as its post step; this is the on-demand path, without
# Terraform.
#
# It carries no files. Everything the VM needs is either in a repository the bootstrap clones or in
# the register it hands over — dotfiles/ owns the agent and Rider configuration, which is the one
# thing that would otherwise have been a copy from this Mac. A converge command with no
# file-copying half also cannot silently overwrite something on the VM.
#
# `ld-vm-setup` loads the register before calling this, so the keys travel. Run this script by hand
# without TF_VAR_loady_ssh_git_base64 in the environment and the bootstrap converges everything
# except the keys, stopping at the clone.
#
# Usage: infra/setup.sh [ssh-host]      default: loady-vm
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${1:-${LD_VM_HOST:-loady-vm}}"
BOOTSTRAP="$ROOT_DIR/bootstrap.sh"
RUNNER="$ROOT_DIR/run-bootstrap.sh"
SEND_TREE="$ROOT_DIR/send-tree.sh"
REMOTE_DIR=/home/dev/.cache/loady-bootstrap

# ssh forwards this Mac's LC_* to the VM, whose only locale is C.UTF-8; anything else makes every
# perl-based apt step warn. Forward one the VM has.
export LC_ALL=C.UTF-8

setup_failed() {
  local status=$?
  trap - ERR
  echo "ld-vm-setup: failed with status $status" >&2
  echo "Inspect the bootstrap log: ssh $HOST tail -n 200 ~/.local/state/loady-vm/bootstrap/latest.log" >&2
  exit "$status"
}
trap setup_failed ERR

ssh -o ConnectTimeout=10 -o BatchMode=yes "$HOST" true \
  || { echo "ld-vm-setup: cannot reach '$HOST' over SSH with the key in ssh-agent" >&2; exit 1; }

echo "==> bootstrap on $HOST"
register=0
[[ -z "${TF_VAR_loady_ssh_git_base64:-}" ]] || register=1
[[ $register -eq 1 ]] \
  || echo "    (no TF_VAR_loady_ssh_git_base64 in this shell — run 'ld-tfin' in $ROOT_DIR first to carry the keys)"

env_file="$(
  [[ -z "${TF_VAR_loady_ssh_git_base64:-}" ]] \
    || printf 'export LD_SECRET_SSH_GIT_BASE64=%q\n' "$TF_VAR_loady_ssh_git_base64"
)"

# The secrets travel as a 0600 file over stdin rather than as process arguments. run-bootstrap.sh
# moves that file to the run's own copy and removes this one as the run starts, and removes the copy
# when it ends.
# The VM reads this repository — scripts/, compose/, dotfiles/, agents/ — but does not clone it:
# it is the Mac's, and the VM reaches Azure DevOps only (AGENTS.md rule 3). So send it first.
"$SEND_TREE" "$HOST"

# shellcheck disable=SC2029  # REMOTE_DIR is this script's own constant, and expanding it here is
# what puts the path in the remote command.
ssh "$HOST" "install -d -m 700 $REMOTE_DIR"
scp -q "$BOOTSTRAP" "$RUNNER" "$HOST:$REMOTE_DIR/"
# shellcheck disable=SC2029
printf '%s\n' "$env_file" | ssh "$HOST" "umask 077 && cat >$REMOTE_DIR/environment"
# The bootstrap runs as a systemd unit, so this connection carries only its log: losing it loses
# nothing, and running this again attaches to the run still in progress. The VM's login shell is
# zsh after the first run, hence bash explicitly.
ssh -t "$HOST" "bash $REMOTE_DIR/run-bootstrap.sh"

trap - ERR
# The bootstrap schedules the reboot Ubuntu asks for on a 15-second timer, so this normally returns
# before it lands; without a word here the next ssh times out for no visible reason.
if ssh -o BatchMode=yes "$HOST" 'test -f /var/run/reboot-required' 2>/dev/null; then
  echo "==> $HOST is current and rebooting (Ubuntu required it); SSH is back in about a minute"
else
  echo "==> $HOST is current"
fi
