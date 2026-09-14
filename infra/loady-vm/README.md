# The loady-vm Terraform root

Creates one VM, `loady-vm`, on `pve-2` from the Ubuntu Server cloud image: 16 cores of type `host`,
32 GB without ballooning, a 300 GB raw disk on `local-zfs` (ext4 root, grown on first boot), VirtIO
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

State is local (`terraform.tfstate` here, gitignored). It holds the Proxmox password and a Tailscale
key in clear, so it is never committed; `docs/manual-secrets.md` covers losing it.

## The image

`variables.tf` pins the Ubuntu cloud image. Its codename must be one that
`packages.microsoft.com/repos/azure-cli` publishes, because the bootstrap installs `az` from there
and a missing codename fails the run on exactly the image it targets. **Checked 2026-09-14:
`resolute` is published**, and that is what the default points at. Before moving to a newer image:

```bash
curl -sS https://packages.microsoft.com/repos/azure-cli/dists/ | grep '<codename>/'
```

Nothing else is codename-gated: PowerShell is not installed at all, `sqlcmd` comes from a GitHub
release, and the Functions Core Tools come from npm — all three deliberately, because the
`packages.microsoft.com/.../prod` repository lags new Ubuntu releases badly.

## Install, in order

1. **Keys and the Bitwarden item.** `docs/manual-secrets.md`, all of it: the Mac's key to the VM,
   the passphrase-less copy of the Azure DevOps key, a new GitHub key, the `loady-vm/keys` item,
   and the two `.tf-vars` lines uncommented.

2. **The name, on the Mac.** `loady-vm` is the LAN address permanently, in `/etc/hosts`;
   `/etc/hosts` wins over every resolver, so off the LAN use the tailnet name, which the hosts
   entry does not shadow.

   ```bash
   grep -q ' loady-vm$' /etc/hosts || echo '192.168.1.51 loady-vm' | sudo tee -a /etc/hosts
   ```

   Then `~/.ssh/config`, so `ssh`, `ld-vm-setup` and Rider agree on how to reach it:

   ```sshconfig
   Host loady-vm loady-vm-ts
       User dev
       IdentityFile ~/.ssh/loady/loady-vm/id_ed25519
       AddKeysToAgent yes
       ServerAliveInterval 30
       ServerAliveCountMax 3

   Host loady-vm-ts
       HostName loady-vm.tail409f27.ts.net
   ```

3. **Defaults.** Check `variables.tf` against the live host: `ipv4_cidr` (`192.168.1.51/24`) free
   on the LAN and outside the router's DHCP pool, `ipv4_gateway` right for that LAN, `vm_id` (`201`)
   free on the node. Override there or with `TF_VAR_*`.

4. **The shell.** Add to `~/.zprofile` and `~/.zshrc` on the Mac:

   ```zsh
   [ -f "$HOME/loady-vm/scripts/loady-shell.zsh" ] && source "$HOME/loady-vm/scripts/loady-shell.zsh"
   ```

   and remove the four old `ld-*` aliases if they are still there — they point at a path that no
   longer exists.

5. **Create it, from the Mac**, in this directory:

   ```bash
   ld-tfin
   terraform plan
   terraform apply
   ```

   The apply creates the VM, waits for SSH, runs the bootstrap with the Tailscale key and the two
   SSH keys, ends with a version table, and reboots the VM seconds later when Ubuntu requires it.
   If the post step fails, fix the cause and apply again — the bootstrap converges, so a rerun is
   safe.

6. **Reserve the address** on the router, outside the DHCP pool.

7. **Tailscale console**, only if device approval is on: approve `loady-vm`.

8. **Sign in on the VM.** Each of these is a browser or device flow that cannot be handed over as a
   token, so they are run through `ld-vm` from the Mac rather than by logging in:

   ```bash
   ld-vm bw login        # then unlock per session, as on the Mac
   ld-vm 'az login'
   ld-vm claude          # signs in on first run
   ld-vm codex
   ```

9. **Run it**: `ld-vm ld-reset`, `ld-vm ld-start`, `ld-vm ld-fe`. Then open the frontend in the
   Mac's browser through forwarding and confirm a request reaches a function host through `:7000` —
   that is the check that proves the Linux-specific fixes.

10. **Rider**: the procedure in `docs/remote-development.md`, then verify indexing, a build, a test
    run, a breakpoint and a push. Confirm the `.idea` directory Rider creates is
    `backend/.idea/.idea.Loady/.idea`; if it is not, correct `RIDER_DIR` in `dotfiles/sync.sh`.

## Operate

- **Anything on the VM without logging in**: `ld-vm <command>` runs it in the VM's login shell from
  the checkout — `ld-vm ld-status`, `ld-vm 'ld-start --public'`, `ld-vm 'cd ~/loady-vm && git status'`.
- **Power**: `vm-start loady`, `vm-stop loady`, `vm-status`. Starting one workstation VM stops the
  other.
- **Converge or upgrade**: `ld-tfin && ld-vm-setup` from here (the SSH keys travel), `ld-vm-setup`
  from anywhere (everything else), or `terraform apply` (the same post step). Every run upgrades
  packages within the configured Ubuntu release, Docker, the SDKs, the CLIs and the agents,
  rewrites only what differs, and reboots seconds later when Ubuntu requires it.
- **Rotate a key**: update the field in Bitwarden, then `ld-tfin && ld-vm-setup`.
- **Change what the VM has**: edit `bootstrap.sh`, then either command above.

Each bootstrap streams its output to the caller and writes the same to a 0600 log inside the VM,
with a stable `latest.log` symlink; logs older than 30 days are removed automatically.

```bash
ld-vm 'tail -n 200 ~/.local/state/loady-vm/bootstrap/latest.log'
terraform output bootstrap_log
```

## Lost access

The bootstrap joins the tailnet with `--ssh`, so a lost or rotated key is `tailscale ssh
dev@loady-vm` from the Mac and a new `authorized_keys`, not a rebuild. Both doors gone at once is a
rebuild: the `dev` user has no password, so the Proxmox console cannot log in.

## Rebuild

```bash
ld-tfd            # refuses while the VM holds uncommitted or unpushed work
ld-tfd --force    # discards it
```

`scripts/rebuild-loady-vm.zsh` checks the checkout and every worktree, runs `ld-tfin`, destroys,
drops the destroyed machine's host keys from `~/.ssh/known_hosts` so Terraform can connect to its
replacement, then applies. The refusal matters more here than it would elsewhere: nothing on this
machine commits automatically, so a dirty tree is the normal state and the disk is its only copy.

Then continue at the sign-in step above.
