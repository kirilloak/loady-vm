#!/usr/bin/env zsh
# Converge or rebuild the development VM. Run from the Mac; this is `ld-tfd`.
#
# Converges the VM when one is already there: runs the bootstrap, which upgrades the packages, the
# SDKs, the CLIs and the agents and rewrites whatever differs. `--rebuild` destroys it first and
# builds it again from the cloud image.
#
# The VM is disposable, but its working trees are not: under AGENTS.md rule 2 nothing commits
# automatically, so uncommitted and unpushed work is the normal state on that machine and the disk
# is the only copy of it. A rebuild refuses while any exists — in loady-one, in ~/loady-vm, which is
# this repository's own checkout there, and in every worktree — and --force is the only way past.
set -euo pipefail

repo_root="${0:A:h:h}"
root="$repo_root/infra"
host="${LD_VM_HOST:-loady-vm}"

rebuild=false
force=false
for arg in "$@"; do
  case "$arg" in
    --rebuild) rebuild=true ;;
    --force) force=true ;;
    *)
      print -ru2 -- "usage: ld-tfd [--rebuild] [--force]   # converge the development VM, or rebuild it"
      exit 2
      ;;
  esac
done

# An unreachable VM is already gone, and that is fine; one that is about to be destroyed while
# reachable gets inspected first.
if [[ "$rebuild" == true && "$force" != true ]] \
  && ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" true 2>/dev/null; then
  # Written for bash: the VM's login shell is zsh, which aborts on an unmatched glob, and an empty
  # worktrees directory is exactly that.
  check='
    for r in ~/loady-one ~/loady-vm; do
      [ -d "$r/.git" ] || continue
      n="$(basename "$r")"
      git -C "$r" status --porcelain | sed "s|^|$n: |"
      git -C "$r" fetch -q origin 2>/dev/null || true
      git -C "$r" log --oneline --branches --not --remotes 2>/dev/null | sed "s|^|$n unpushed: |"
    done
    for w in ~/loady-worktrees/*/ ~/loady-worktrees/*/*/; do
      [ -d "$w/.git" ] || [ -f "$w/.git" ] || continue
      git -C "$w" status --porcelain | sed "s|^|$(basename "$w"): |"
      git -C "$w" log --oneline --branches --not --remotes 2>/dev/null | sed "s|^|$(basename "$w") unpushed: |"
    done
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

if [[ "$rebuild" == true ]]; then
  print -- "==> Destroying $host"
  terraform destroy -auto-approve

  # The replacement answers on the same name and address with new host keys; drop the old ones
  # before Terraform's post step connects to it.
  ipv4="$(sed -nE 's/^ *default *= *"([0-9.]+)\/[0-9]+"/\1/p' variables.tf | head -n 1)"
  ssh-keygen -R "$host" >/dev/null 2>&1 || true
  [[ -z "$ipv4" ]] || ssh-keygen -R "$ipv4" >/dev/null 2>&1 || true

  print -- "==> Creating $host"
else
  # apply on an existing VM is the converge: the post step sends this repository over and reruns
  # the bootstrap, whose every step rewrites only what differs. It creates the VM when there is
  # none, which is why this is also the first-build path.
  print -- "==> Converging $host"
fi
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
print -- "$host is bootstrapped and ready. First build? Continue at the account steps in infra/README.md."
