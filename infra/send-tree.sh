#!/usr/bin/env bash
# Send this repository to the VM, as files rather than as a checkout.
#
# The repository is a Mac thing: it is edited, committed and pushed there, and under AGENTS.md rule
# 3 the VM reaches exactly one git service, which does not host this. The VM still needs what is in
# it — scripts/ for the ld-* functions its login shell sources, compose/ for the stack and the
# function-host ports the firewall opens, dotfiles/ for the agent and Rider configuration, agents/
# behind the symlinks link-agent-files.sh makes — so the Mac sends it.
#
# ~/loady-vm on the VM is therefore a copy, and this overwrites it. Edit the setup on the Mac.
#
# Usage: infra/send-tree.sh [ssh-host]      default: loady-vm
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${1:-${LD_VM_HOST:-loady-vm}}"
DEST=loady-vm

command -v rsync >/dev/null || { echo "send-tree: rsync is not installed on this Mac" >&2; exit 1; }

# This runs before the bootstrap has installed anything, and whether the cloud image carries rsync
# is not something to depend on. The bootstrap keeps it installed from then on.
ssh -o BatchMode=yes "$HOST" 'command -v rsync >/dev/null || sudo apt-get install -y rsync' \
  || { echo "send-tree: no rsync on $HOST and it could not be installed" >&2; exit 1; }

echo "==> sending the loady-vm tree to $HOST"
# --delete so a file removed on the Mac goes on the VM too: a stale ld-* script or compose file is
# worse than a missing one. The exclusions are the things that are either the Mac's alone or are
# state rather than source.
rsync -a --delete \
  --exclude '.git/' \
  --exclude '.terraform/' \
  --exclude 'terraform.tfstate*' \
  --exclude '.tfplan' \
  --exclude '.DS_Store' \
  "$ROOT_DIR/" "$HOST:$DEST/"
