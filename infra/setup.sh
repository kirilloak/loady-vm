#!/usr/bin/env bash
# Converge the development VM from the Mac, as often as wanted: runs bootstrap.sh on the VM over
# SSH with the SSH keys from Bitwarden. The VM itself comes from the Terraform root beside this
# file, which runs the same bootstrap as its post step; this is the on-demand path, without
# Terraform.
#
# It carries no files but the bootstrap itself. Everything else the VM needs is in one of the two
# repositories the bootstrap clones — including this one, which the VM checks out from GitHub and
# the founder commits to there. A converge with no file-copying half cannot overwrite work sitting
# uncommitted on that machine.
#
# Run it from this root after `ld-tfin`, which exports the register as TF_VAR_loady_ssh_git_base64,
# TF_VAR_github_ssh_base64 and TF_VAR_github_token; run it from anywhere without, and the bootstrap
# converges everything except the keys, stopping at the clones.
#
# Usage: infra/setup.sh [ssh-host]      default: loady-vm
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${1:-${LD_VM_HOST:-loady-vm}}"
BOOTSTRAP="$ROOT_DIR/bootstrap.sh"
RUNNER="$ROOT_DIR/run-bootstrap.sh"
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
[[ -n "${TF_VAR_loady_ssh_git_base64:-}" && -n "${TF_VAR_github_ssh_base64:-}" ]] \
  || echo "    (no keys in this shell — run 'ld-tfin' in $ROOT_DIR first to carry them)"

# Each is optional here so a converge without the register still upgrades the machine and stops at
# the clone it cannot do, rather than refusing to run at all.
env_file="$(
  [[ -z "${TF_VAR_loady_ssh_git_base64:-}" ]] \
    || printf 'export LD_SECRET_SSH_GIT_BASE64=%q\n' "$TF_VAR_loady_ssh_git_base64"
  [[ -z "${TF_VAR_github_ssh_base64:-}" ]] \
    || printf 'export LD_SECRET_SSH_GITHUB_BASE64=%q\n' "$TF_VAR_github_ssh_base64"
  [[ -z "${TF_VAR_github_token:-}" ]] \
    || printf 'export LD_SECRET_GITHUB_TOKEN=%q\n' "$TF_VAR_github_token"
)"

# The secrets travel as a 0600 file over stdin rather than as process arguments. run-bootstrap.sh
# moves that file to the run's own copy and removes this one as the run starts, and removes the copy
# when it ends.
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
