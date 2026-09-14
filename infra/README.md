# The loady-vm Terraform root

Creates one VM, `loady-vm`, on `pve-2` from the Ubuntu Server cloud image: 16 cores of type `host`,
32 GB without ballooning, a 500 GB raw disk on `local-zfs` (ext4 root, grown on first boot), VirtIO
on `vmbr0` with a static address, serial console, no guest agent. Proxmox's cloud-init drive creates
the `dev` user with the Mac's key and sets the address; that is the only image-level configuration.
Everything else is `bootstrap.sh`.

Architecture and daily use: `docs/remote-development.md`. Secrets: `docs/manual-secrets.md`.

`on_boot` is false on purpose. Only one workstation VM may run at a time, so a host reboot must not
bring both up; `vm-start loady` is what starts this one, and it stops the other first.

No swap, and no balloon device: swapping would turn an exceptional memory overrun into sustained
disk latency, and a host that can shrink this VM under pressure makes the guest OOM-kill its own
build. The VM trades guest-side hardening for build throughput — `mitigations=off`, `noatime`,
`/tmp` on tmpfs, no guest I/O scheduler, raised open-file limits — which is deliberate: only the
founder's own code runs in this guest.

State is local (`terraform.tfstate` here, gitignored). It holds the Proxmox password in clear, so it
is never committed; `docs/manual-secrets.md` covers losing it.

## The image

`variables.tf` pins the Ubuntu cloud image. Its codename must be one that
`packages.microsoft.com/repos/azure-cli` publishes, because the bootstrap installs `az` from there
and a missing codename fails the run on exactly the image it targets. **Checked 2026-09-14:
`resolute` is published**, and that is what the default points at. Before moving to a newer image:

```bash
curl -sS https://packages.microsoft.com/repos/azure-cli/dists/ | grep '<codename>/'
```

`sqlcmd` comes from `packages.microsoft.com/ubuntu/<release>/prod` as `mssql-tools18`, which is
codename-gated the same way and publishes for this one (checked 2026-09-14). PowerShell is not
installed at all, and the Functions Core Tools come from npm.

If that filename already exists in Proxmox but is absent from this root's state, the first apply
replaces that one unmanaged file from the configured URL and takes ownership of it. This makes a
retry converge after a download that completed remotely but failed before Terraform recorded it.

## Install, in order

1. **The keys, and the Bitwarden items.** `docs/manual-secrets.md`: a passphrase-less copy of the
   existing `~/.ssh/loady/id_rsa` as `ssh_loady_git_base64` on `workstation/loady`, for Azure
   DevOps; `ssh_dev_vm_github_base64` and `pat` on the items `.tf-vars` already names, for GitHub.
   No new keys are created and no profile changes: both keys are already registered where they are
   used, and the Mac logs in to the VM with its existing `~/.ssh/id_ed25519`.

2. **The name, on the Mac.** `loady-vm` is the LAN address permanently, in `/etc/hosts`. The VM is
   reachable on the LAN only.

   ```bash
   grep -q ' loady-vm$' /etc/hosts || echo '192.168.1.51 loady-vm' | sudo tee -a /etc/hosts
   ```

   Then the SSH config, so `ssh`, `ld-vm-setup` and Rider agree on how to reach it. On this Mac
   `~/.ssh/config` is a **symlink** into the founder's settings repository
   (`settings/macos/dotfiles/.sshconfig`), so this is a tracked change there, not a private edit:

   ```sshconfig
   Host loady-vm
       User dev
       IdentityFile ~/.ssh/id_ed25519
       IdentitiesOnly yes
       AddKeysToAgent yes
       UseKeychain yes
       ServerAliveInterval 30
       ServerAliveCountMax 3
   ```

   While there, pin the Azure DevOps key by **hostname** as well. The existing `Host loady` alias
   never matches, because the remote is `git@ssh.dev.azure.com:v3/...`; SSH falls through to
   `Host *` and offers every key in the agent, which on this Mac means three wrong keys before the
   right one. Azure DevOps documents that it may reject the request outright instead of trying the
   next key, so make it deterministic:

   ```sshconfig
   Host ssh.dev.azure.com
       IdentityFile ~/.ssh/loady/id_rsa
       IdentitiesOnly yes
   ```

   `IdentitiesOnly yes` is what stops the agent's other keys being offered first. The VM does not
   need this: `bootstrap.sh` binds each checkout to its own key with `core.sshCommand`, which
   already carries `-o IdentitiesOnly=yes`.

3. **Defaults.** Check `variables.tf` against the live host: `ipv4_cidr` (`192.168.1.51/24`) free
   on the LAN and outside the router's DHCP pool, `ipv4_gateway` right for that LAN, `vm_id` (`201`)
   free on the node. Override there or with `TF_VAR_*`.

4. **The shell.** Add to `~/.zprofile` and `~/.zshrc` on the Mac:

   ```zsh
   [ -f "$HOME/loady-vm/scripts/loady-shell.zsh" ] && source "$HOME/loady-vm/scripts/loady-shell.zsh"
   ```

   and remove the four old `ld-*` aliases if they are still there — they point at a path that no
   longer exists.

5. **Create it, from the Mac**, with one command from any directory:

   ```bash
   ld-tfd
   ```

   `ld-tfd` loads the Bitwarden register, initializes Terraform, applies with auto-approval, waits
   for SSH, runs the bootstrap with the two Git keys, which clones both `loady-one` and this
   repository, restores and builds the C# solution, installs frontend dependencies, pulls every
   Compose image, and waits for any required Ubuntu reboot to finish. Any step failing stops the
   command; fix the cause and run it again.

   With a VM already there it converges that one rather than replacing it, which is also how an
   upgrade is run. `ld-tfd --rebuild` destroys it first and builds it again from the cloud image,
   and refuses while reachable uncommitted or unpushed work exists unless `--force` is explicit.

6. **Reserve the address** on the router, outside the DHCP pool.

7. **Sign in on the VM.** Each of these is a browser or device flow that cannot be handed over as a
   token, so they are run through `ld-vm` from the Mac rather than by logging in:

   ```bash
   ld-vm bw login        # then unlock per session, as on the Mac
   ld-vm 'az login'
   ld-vm claude          # signs in on first run
   ld-vm codex
   ```

8. **Run it**: `ld-vm ld-reset`, then in Rider run `be-seeder`, `be-test-data-seeder` and
   `stack-all`. Open the frontend in the Mac's browser through forwarding and confirm a request
   reaches a function host through `:7000` — that is the check that proves the Linux-specific
   fixes.

9. **Rider**: the procedure in `docs/remote-development.md`, then verify indexing, a build, a test
   run, a breakpoint and a push. Confirm the `.idea` directory Rider creates is
   `backend/.idea/.idea.Loady/.idea`; if it is not, correct `RIDER_DIR` in `dotfiles/sync.sh`.

## Operate

- **Anything on the VM without logging in**: `ld-vm <command>` runs it in the VM's login shell from
  the checkout — `ld-vm ld-reset`, `ld-vm ld-cosmos-cert`, `ld-vm 'git status'`. Applications run
  from Rider.
- **Power**: `vm-start loady`, `vm-stop loady`, `vm-status`. Starting one workstation VM stops the
  other.
- **Converge or upgrade**: `ld-tfd`, which loads the register itself, or `ld-tfin && ld-vm-setup`
  to converge without Terraform (`ld-tfin` is what carries the keys into the shell; without it the
  run stops at the clones). Every run upgrades packages within the configured Ubuntu release,
  Docker, the SDKs, the CLIs and the agents, rewrites only what differs, and reboots seconds later
  when Ubuntu requires it.
- **Rotate a key**: update the field in Bitwarden, then `ld-tfin && ld-vm-setup`.
- **Change what the VM has**: edit `bootstrap.sh`, then either command above. The VM's own
  `~/loady-vm` is a checkout of this repository, so that edit can be made and committed there;
  the Mac pulls it before the next Terraform run.

Each bootstrap runs on the VM as the systemd unit `loady-bootstrap`, started by `run-bootstrap.sh`,
and the caller holds nothing but its log. The run therefore survives the connection that started it:
the bootstrap replaces `openssh-server` under itself and takes a quarter of an hour, so a session
that owned it would lose it to any dropped channel. A caller that disconnects re-attaches by running
the same command again, which follows the run already in progress rather than starting a second one.

Each bootstrap streams its output to the caller and writes the same to a 0600 log inside the VM,
with a stable `latest.log` symlink; logs older than 30 days are removed automatically. While a run
is live, `journalctl` knows nothing about it: the unit's output goes to `/run/loady-bootstrap/log`,
which is what the caller is following.

```bash
ld-vm 'tail -n 200 ~/.local/state/loady-vm/bootstrap/latest.log'
terraform output bootstrap_log
```

## Lost access

The Mac's `~/.ssh/id_ed25519` is the only door, so a lost or rotated key is a rebuild: the `dev` user
has no password, so the Proxmox console cannot log in either.

## Converge and rebuild

```bash
ld-tfd                      # converge the VM that is there, or build the first one
ld-tfd --rebuild            # destroy and build again; refuses while the VM holds unpushed work
ld-tfd --rebuild --force    # discards it
```

`scripts/rebuild-loady-vm.zsh` checks both checkouts and every worktree, runs `ld-tfin`, destroys,
drops the destroyed machine's host keys from `~/.ssh/known_hosts` so Terraform can connect to its
replacement, then applies. The refusal matters more here than it would elsewhere: nothing on this
machine commits automatically, so a dirty tree is the normal state and the disk is its only copy.

Then continue at the sign-in step above.
