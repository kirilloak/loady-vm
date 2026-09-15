# Result: take GitHub out of the setup, and the loady-vm repository off the VM

Plan: [2026_09_14_no_github_on_the_vm.md](2026_09_14_no_github_on_the_vm.md)

## Status

Partial: the bootstrap runs clean end to end on a live VM and stops only at the clone, which needs
the Bitwarden register the founder loads. Everything before that is verified on the machine.

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

- Under the runner, `==> bootstrap started` prints twice: the script's `tee` and the unit's stdout
  capture overlap. Cosmetic, not chased.
- The Loady RSA key is on Azure DevOps but **not** on GitHub. `AGENTS.md`, `infra/variables.tf` and
  `docs/manual-secrets.md` all claimed both; the check behind that claim was run on the Mac, where
  ssh falls through to `~/.ssh/id_ed25519` and authenticates with that instead. Step 4 fixes the
  text.

## Defects found by running it, and fixed

Each of these stood between the founder and a working `ld-tfd`:

1. `cloud-init` exits 2 on a degraded-but-done boot; `run_with_progress` died before the `case` that
   tolerates it could run. Split into `try_with_progress` (returns) and `run_with_progress` (dies).
2. The `openssh-server` upgrade closes `ssh.socket` and kills the session running the script.
   Shielded with `policy-rc.d`, plus `NEEDRESTART_SUSPEND=1`, which needrestart needs because it
   ignores `policy-rc.d`.
3. `dotnet-install.sh` fetches 200 MB with a curl carrying no timeout, and hung nine minutes on a
   silent Akamai edge. Bounded at 10m per attempt, three attempts.
4. The tree-sending `local-exec` ran 14s after VM creation, before sshd was up. Moved after the
   first `remote-exec`, which blocks on the connection block.
5. A rebuilt VM reuses the address, so the Mac's stale host key wedged `send-tree.sh`. It now drops
   the stale entry and relearns.
6. Microsoft's prod repo is signed by a year-stamped key absent from `microsoft.asc`
   (`NO_PUBKEY EE4D7792F748182B`). Pointed at `microsoft-2025.asc`.
7. `apt_repo` fetched a key only when the keyring was absent, so a wrong keyring could never be
   replaced and every update failed forever. It now records the key URL and re-fetches when it
   changes.
8. `gpg --dearmor` opens `/dev/tty`, which the systemd unit does not have. `--batch --no-tty`.
9. Upgrading the `systemd` package restarts dbus, and `systemctl is-active` then answers "Transport
   endpoint is not connected" — which `run-bootstrap.sh` read as the run ending. It now waits on the
   status file and requires five consecutive negative answers before believing the unit is gone.
   The run itself was unaffected, which is the point of the unit.

## Verification performed

- `shellcheck`, `bash -n` on every shell file touched: pass.
- `terraform fmt -check`, `terraform validate`: pass.
- Live on the VM: the restart shield keeps sshd up across an `openssh-server` reinstall; the
  detached unit survives its caller; a full run reached the clone step in 227s.
- `zsh -n` on both zsh scripts, `docker compose config` with `LOADY_REPO_DIR` set: pass.
- No `github` left outside `AGENTS.md` rule 3 and the correction note in `docs/manual-secrets.md`.
- A full run on the live VM reached the clone in 303s, with every earlier step green. After it:
  `rg` 15.1.0, `fd` 10.3.0, `shellcheck` 0.11.0 from apt; `sqlcmd` from `mssql-tools18` 18.7.1.1;
  dotnet 10.0.401; Node 22.23.2; Docker 29.8.0; one git identity; `~/loady-vm` present with no
  `.git`; zero GitHub entries in the VM's `known_hosts`.
- `send-tree.sh` verified against the live VM, including the stale-host-key path.
- The runner's attach path verified: a second call printed "already running; attaching to it" and
  followed the same run to its end.
- Not yet run: the clone, restore, build, yarn install and image pulls, which need the register.
