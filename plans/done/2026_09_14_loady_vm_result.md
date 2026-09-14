# Result: Loady remote development VM

## Plan

`plans/2026_09_14_loady_vm.md`

## Status

**Partial — every step that does not need the Proxmox host or the founder's key material is
complete.** Steps 1-13 are done, verified, committed and pushed. Steps 14-19 create and verify the
machine and are listed under Manual actions: they need the SSH keys, the fields on the
`workstation/loady` Bitwarden item, and a host to build on.

## Files

Everything below was created by this task unless marked.

**Repository**
- `AGENTS.md` — the five rules, knowledge ownership, plan and result conventions, working rules
- `CLAUDE.md` — the single line `@AGENTS.md`
- `README.md` — replaced the one-line placeholder; layout and the command table
- `.gitignore` — Terraform state and working directories; `.tf-vars` and the lock file stay tracked

**Agent instruction files** (step 2)
- `agents/backend/CLAUDE.md` — from `~/Repositories/kirill/settings/macos/agents/LOADY.md`, with
  `.NET 9` corrected to `.NET 10` on line 3 (`backend/global.json` pins `10.0.100`)
- `agents/infrastructure/CLAUDE.md` — from `LOADY-INFRA.md`, unmodified

**Compose and the function hosts**
- `compose/loady-vm.yaml` — the five services, `extra_hosts` on `apim`, explicit `127.0.0.1`
  bindings, healthchecks on redis and sqlserver, `nginx.conf` mounted read-only from the checkout
- `compose/processes.json` — the eleven function hosts, their ports, and the start-up pauses

**Scripts**
- `scripts/lib.sh` — shared helpers; `ld_repo` resolves the worktree the caller is standing in
- `scripts/loady-shell.zsh` — every `ld-*` and `vm-*` function, and `ld-tfin`
- `scripts/link-agent-files.sh` — the symlinks and `.git/info/exclude` entries
- `scripts/slot.sh` — the `loadystack` slot
- `scripts/ld-dev.sh` — the Linux replacement for `backend.ps1`
- `scripts/ld-reset.sh` — container reset plus the compose drift warning
- `scripts/ld-migrate.sh` — the three EF entry points
- `scripts/ld-stream.sh` — worktree new/list/remove
- `scripts/vm.sh` — `vm-start`/`vm-stop`/`vm-status`, switching between the two workstation VMs
- `scripts/rebuild-loady-vm.zsh` — `ld-tfd`

**Terraform** (`infra/`)
- `versions.tf`, `provider.tf`, `variables.tf`, `main.tf`, `outputs.tf`
- `.tf-vars` — all three items live: the shared Proxmox and Tailscale ones, and `workstation/loady`
  (`06e7a977-9e1f-4641-8e36-b4c50096047a`) for the single git key
- `bootstrap.sh` — the whole guest
- `setup.sh` — converge from the Mac
- `tailscale-api.sh` — tailnet registration cleanup
- `README.md` — install, operate, lost access, rebuild
- `.terraform.lock.hcl` — written by `terraform init`, tracked

**dotfiles**
- `dotfiles/sync.sh`, `dotfiles/README.md`
- `dotfiles/ai/instructions.md` — the VM's global agent instructions
- `dotfiles/ai/claude/settings.json` — including the git deny list that enforces rule 2
- `dotfiles/ai/codex/config.toml`
- `dotfiles/rider/forwardedPorts.xml` — the six always-on ports
- `dotfiles/rider/indexLayout.xml`, `dotfiles/rider/README.md`

**Docs**
- `docs/remote-development.md`, `docs/manual-secrets.md`

**Outside this repository**
- `~/loady-one/backend/CLAUDE.md`, `~/loady-one/backend/AGENTS.md` — symlinks into this repository
- `~/loady-one/.git/info/exclude` — three entries appended; local only, never pushed
- `~/Repositories/kirill/settings/macos/dotfiles/.zprofile`, `.zshrc` — source
  `~/loady-vm/scripts/loady-shell.zsh`; the four obsolete Loady aliases were removed

## Manual actions

In order. Steps 14-19 of the plan.

1. ~~**Commit and push this repository.**~~ Done. `agents/backend/CLAUDE.md` and
   `agents/infrastructure/CLAUDE.md` are on `origin/main`, so the originals under
   `~/Repositories/kirill/settings/macos/agents/` are now safe to delete at action 9.

2. **Fill the `workstation/loady` Bitwarden item** — one field. Copy `~/.ssh/loady/id_rsa`, strip the
   passphrase from the copy, store it as `ssh_loady_git_base64`, shred the copy
   (`docs/manual-secrets.md` has the commands). No new keys and no profile changes.
   *Verify:* the copy authenticates with no prompt to **both** `git@ssh.dev.azure.com` and
   `git@github.com`.

3. **`/etc/hosts` and `~/.ssh/config`** on the Mac — `infra/README.md` step 2. Reserve
   `192.168.1.51` on the router, outside the DHCP pool.

4. ~~**Source the shell file** from `~/.zprofile` and `~/.zshrc`, and delete the four dead `ld-*`
   aliases in `~/.zshrc`.~~ Done in the tracked settings repository; a fresh login shell resolves
   all Loady commands as functions.

5. **Confirm `192.168.1.51` and `vm_id` 201 are free** on the live host, then run `ld-tfd` from any
   directory. It loads the register, initializes Terraform, and creates the fully bootstrapped VM.

6. **Sign in on the VM**: `ld-vm bw login`, `ld-vm 'az login'`, `ld-vm claude`, `ld-vm codex`.

7. **Prove the request path**: `ld-vm ld-reset`, `ld-vm ld-start`, `ld-vm ld-fe`, then the frontend
   in the Mac's browser and one request through `:7000` reaching a function host. This is the step
   the two Linux-only fixes exist to pass.

8. **Prove the streams**: two worktrees, build in both, confirm the second `ld-start` is refused by
   name, then remove both.

9. **Connect Rider**, confirm the `.idea` directory name is `.idea.Loady` and correct `RIDER_DIR`
   in `dotfiles/sync.sh` if it is not, then retire the launchd watcher
   (`launchctl bootout gui/$(id -u)/com.kirill.watch-agents`, remove the plist) and delete the two
   original files under `~/Repositories/kirill/settings/macos/agents/` — only after action 1.

## Notes

- **Follow-up on 2026-09-14:** the Terraform root moved from `infra/loady-vm/` to `infra/`, keeping
  its local state and initialized providers. An apply now replaces a colliding unmanaged Proxmox
  image, requires the Git key, and fails unless the C# restore/build, frontend install, and Compose
  image pull all succeed. Following Costfluent's `cf-tfd` pattern, `ld-tfd` opens the Bitwarden
  session before entering the rebuild script, clears LAN and Tailscale host keys, and waits for the
  post-bootstrap reboot to finish, so creation and rebuilding require only that command. The
  bootstrap also verifies the VM login shell exposes the operational `ld-*` functions, including
  `ld-reset`, before it can succeed.
- **Three keys became one, on request.** The plan had a dedicated Mac→VM ed25519, the Azure DevOps
  RSA key, and a new GitHub ed25519. The founder asked to reuse existing keys rather than create any.
  Verified on 2026-09-14 that `~/.ssh/loady/id_rsa` already authenticates to **both**
  `ssh.dev.azure.com` and `github.com` (as `kirilloak`), so it is now the single key the bootstrap
  places for every git remote, and the Mac logs in to the VM with its existing `~/.ssh/id_ed25519`
  (public half only, so reuse there costs nothing). The Bitwarden item went from three fields to
  one, `variables.tf` from two key variables to one, and no SSH profile needs a new entry anywhere.
  The tradeoff, stated in `docs/manual-secrets.md`: one key now reaches both remotes, and its
  passphrase-less copy lives on the VM.
- **`vm-start`/`vm-stop` replaced the planned `ld-up --takeover`.** Asked for mid-implementation:
  short commands that switch between the two workstation VMs by name, where starting one stops the
  other. `scripts/vm.sh` does that; `ld-up`/`ld-down` remain as wrappers naming this VM. The
  shutdown is a graceful ACPI shutdown with a wait, announced before it happens, and `--no-switch`
  refuses instead. Plan decision 3 is superseded.
- **`ld-power.sh` was deleted** after being written, replaced by `scripts/vm.sh` for the above.
- **Two bugs were found and fixed by the verification, not by review.** `dotfiles/sync.sh` resolved
  manifest paths against the repository root rather than `dotfiles/`, so every tracked file read as
  missing. `link-agent-files.sh` used `git rev-parse --git-common-dir`, which prints a *relative*
  path when run inside the repository, so the first run appended the exclusions to
  **`loady-vm`'s own** `.git/info/exclude` instead of `loady-one`'s; those three stray lines were
  removed and the path is now resolved against the checkout.
- **The agent instruction files were not ignored by `loady-one`** as the plan assumed for
  `CLAUDE.md`/`AGENTS.md` — only `.idea` was. `link-agent-files.sh` checks with `git check-ignore`
  and adds the entries when they are missing, which is what happened here, so the outcome is the
  same and the assumption is no longer load-bearing.
- **`agents/infrastructure/CLAUDE.md` says .NET 9** and was left alone: it describes the
  `loady-infrastructure` repository, which is not checked out on this machine, so there is no
  evidence either way. It is stored but not linked anywhere for the same reason.
- **`~/loady-one` has 13 modified `packages.lock.json` files** that predate this task. Untouched.
- The Ubuntu image codename was checked against the azure-cli repository on 2026-09-14: `resolute`
  is published, and that is what `variables.tf` points at.

## Verification

Run on the Mac; nothing touched the Proxmox host.

| Check | Result |
|---|---|
| `shellcheck -x` on all 10 bash scripts | pass, clean |
| `bash -n` on all bash scripts | pass |
| `zsh -n` on `loady-shell.zsh`, `rebuild-loady-vm.zsh` | pass |
| every documented `ld-*`/`vm-*` function defined after sourcing | pass, 27 functions |
| no helper function name starts with `_` | pass, 0 matches |
| `terraform init -backend=false` + `validate` | pass, "The configuration is valid" |
| `terraform fmt -check` | pass |
| `docker compose config` with the real checkout | pass; `extra_hosts: host.docker.internal=host-gateway` present, `nginx.conf` resolves to the checkout, all 8 published ports bound to `127.0.0.1` |
| `compose/processes.json` — 11 hosts, 4 groups | pass, matches `backend.ps1` exactly |
| `dotfiles/sync.sh` first sync into scratch | pass, all 6 live files written |
| `dotfiles/sync.sh` rerun | pass, silent no-op |
| `dotfiles/sync.sh` live-side edit | pass, copied back into the repository |
| `dotfiles/sync.sh` both sides edited | pass, conflict recorded, **nothing written**, `--check` reports it, resolution clears it |
| `dotfiles/sync.sh --seed-worktree` | pass, both Rider files placed |
| `link-agent-files.sh` against the real checkout, twice | pass, idempotent |
| `git -C ~/loady-one status` shows no agent file | pass, and the symlinks point into `~/loady-vm` |

Not run, and why: anything needing the VM — the bootstrap, `ld-start`, `ld-dev.sh`, `ld-reset`,
`ld-migrate`, `ld-stream`, `vm.sh` against the live Proxmox API, `terraform plan` against the host,
and the Cosmos emulator on Linux. These are steps 14-19 and the Manual actions above.
