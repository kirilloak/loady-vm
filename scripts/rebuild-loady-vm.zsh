#!/usr/bin/env zsh
# Create or rebuild the development VM. Run from the Mac; this is `ld-tfd`.
#
# The VM is disposable, but its working tree is not: under AGENTS.md rule 2 nothing commits
# automatically, so uncommitted and unpushed work is the normal state on that machine and the disk
# is the only copy of it. This refuses while any exists, in the checkout and in every worktree, and
# --force is the only way past.
set -euo pipefail

repo_root="${0:A:h:h}"
root="$repo_root/infra"
host="${LD_VM_HOST:-loady-vm}"

if (( $# > 1 )) || [[ $# -eq 1 && "$1" != --force ]]; then
  print -ru2 -- "usage: ld-tfd [--force]   # create or rebuild the development VM"
  exit 2
fi

# An unreachable VM is already gone, and that is fine; a reachable one gets inspected first.
if [[ "${1:-}" != --force ]] && ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" true 2>/dev/null; then
  # Written for bash: the VM's login shell is zsh, which aborts on an unmatched glob, and an empty
  # worktrees directory is exactly that.
  check='
    cd ~/loady-one 2>/dev/null || exit 0
    git status --porcelain | sed "s|^|loady-one: |"
    git fetch -q origin 2>/dev/null || true
    git log --oneline --branches --not --remotes 2>/dev/null | sed "s|^|loady-one unpushed: |"
    for w in ~/loady-worktrees/*/ ~/loady-worktrees/*/*/; do
      [ -d "$w/.git" ] || [ -f "$w/.git" ] || continue
      git -C "$w" status --porcelain | sed "s|^|$(basename "$w"): |"
      git -C "$w" log --oneline --branches --not --remotes 2>/dev/null | sed "s|^|$(basename "$w") unpushed: |"
    done
    cd ~/loady-vm 2>/dev/null || exit 0
    git status --porcelain | sed "s|^|loady-vm: |"
    git log --oneline --branches --not --remotes 2>/dev/null | sed "s|^|loady-vm unpushed: |"
  '
  unpushed="$(ssh -o BatchMode=yes "$host" bash -c "${(q)check}")"
  if [[ -n "$unpushed" ]]; then
    print -ru2 -- "ld-tfd: the VM holds work Git has nowhere else. Push it, or pass --force:"
    print -ru2 -- "$unpushed"
    exit 1
  fi
fi

source "$repo_root/scripts/loady-shell.zsh"
cd "$root"
ld-tfin

print -- "==> Destroying $host"
terraform destroy -auto-approve

# The replacement answers on the same name and address with new host keys; drop the old ones before
# Terraform's post step connects to it.
ipv4="$(sed -nE 's/^ *default *= *"([0-9.]+)\/[0-9]+"/\1/p' variables.tf | head -n 1)"
ssh-keygen -R "$host" >/dev/null 2>&1 || true
[[ -z "$ipv4" ]] || ssh-keygen -R "$ipv4" >/dev/null 2>&1 || true

print -- "==> Creating $host"
terraform apply -auto-approve

print -- "==> Waiting for $host to finish rebooting"
vm_ready=false
for _ in {1..36}; do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
    "$host" 'test ! -f /var/run/reboot-required' 2>/dev/null; then
    vm_ready=true
    break
  fi
  sleep 5
done
if [[ "$vm_ready" != true ]]; then
  print -ru2 -- "ld-tfd: $host did not become ready within 180s; inspect the Proxmox console"
  exit 1
fi

print
print -- "$host is fully bootstrapped and ready. Continue at the account steps in infra/README.md."
