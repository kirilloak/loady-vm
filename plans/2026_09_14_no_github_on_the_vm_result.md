# Result: take GitHub out of the setup, and the loady-vm repository off the VM

Plan: [2026_09_14_no_github_on_the_vm.md](2026_09_14_no_github_on_the_vm.md)

## Status

Partial: every file change is done and checked; the run that proves it has not happened, because the
founder is rebuilding the VM.

## Files created or edited

- `infra/run-bootstrap.sh` — new; the bootstrap as a detached systemd unit, so losing the caller's
  channel costs an attach rather than the run.
- `infra/variables.tf`, `infra/README.md` — 500 GB disk; the key description no longer claims GitHub.
- `infra/send-tree.sh` — new; rsyncs this repository to the VM, `.git` and Terraform state excluded,
  installing rsync there first if the cloud image lacks it.
- `infra/bootstrap.sh` — no GitHub anywhere: no `VM_REPO_URL`, no clone of this repository, no
  host-key seeding from `api.github.com`, and rg, fd, shellcheck and sqlcmd from apt
  (`mssql-tools18` off Microsoft's prod repo) instead of GitHub releases. `rsync` added to the
  package list. One git identity. Plus the earlier fixes: cloud-init exit 2 tolerated, the restart
  shield around the upgrade, and the bounded, retried .NET SDK install.
- `infra/setup.sh`, `infra/main.tf` — call the runner, and send the tree before the bootstrap runs;
  Terraform does the sending from the Mac with a `local-exec`.
- `scripts/rebuild-loady-vm.zsh` — `ld-tfd` converges an existing VM; `--rebuild` destroys first.
  The unpushed-work check no longer looks at `~/loady-vm`, which is not a checkout there any more.
- `AGENTS.md` — the "Where work runs" rule and `run-bootstrap.sh` in the knowledge table; rule 3
  rewritten (Loady resources only on the VM, Azure DevOps only, GitHub on the
  Mac alone), rule 5 gained the copy-not-checkout exception, `send-tree.sh` in the knowledge table.
- `docs/manual-secrets.md`, `docs/remote-development.md`, `infra/README.md` — the GitHub claims
  corrected and the `ld-tfd` surface updated.

## Manual actions for the founder

- Rebuild the VM and run `ld-tfin && ld-tfd`. Nothing was fixed on the running VM by hand, by the
  founder's instruction, so the machine that exists now does not reflect any of this.
- `/etc/hosts` on the Mac still has no `loady-vm` entry; it needs root. Without it, pass the host:
  `ld-vm-setup dev@192.168.1.51`.

## Notes

- The Loady RSA key is on Azure DevOps but **not** on GitHub. `AGENTS.md`, `infra/variables.tf` and
  `docs/manual-secrets.md` all claimed both; the check behind that claim was run on the Mac, where
  ssh falls through to `~/.ssh/id_ed25519` and authenticates with that instead. Step 4 fixes the
  text.

## Verification performed

- `shellcheck`, `bash -n` on every shell file touched: pass.
- `terraform fmt -check`, `terraform validate`: pass.
- Live on the VM: the restart shield keeps sshd up across an `openssh-server` reinstall; the
  detached unit survives its caller; a full run reached the clone step in 227s.
- `zsh -n` on both zsh scripts, `docker compose config` with `LOADY_REPO_DIR` set: pass.
- No `github` left outside `AGENTS.md` rule 3 and the correction note in `docs/manual-secrets.md`.
- Not yet run: a bootstrap that ends with status 0, and `send-tree.sh` against a live VM.
