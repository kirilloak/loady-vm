# Remote development: Mac client, Ubuntu VM on Proxmox

The Mac is a thin client. The development workstation is `loady-vm`, an Ubuntu Server VM on the
founder's Proxmox host: the `loady-one` checkout, Rider's backend, the .NET and Node toolchains,
Docker, the local stack and the coding agents all live and run there. The Mac renders the IDE, the
browser and the terminal, and reaches the VM over SSH on the LAN.

Why: the company laptop does not have the CPU or memory to build this solution, the VM is Linux
amd64 like the deployment targets, and Docker is native rather than a VM inside macOS. Remote IDE
work is latency-bound rather than bandwidth-bound, so wired 1 GbE on the LAN is enough.

| Concern | Owner |
|---|---|
| The VM: sizing, disk, address, the `dev` user, every manual step | `infra/` and its `README.md` |
| What is installed inside it, and how it is hardened | `infra/bootstrap.sh` |
| Converging it from the Mac | `infra/setup.sh` (`ld-vm-setup`) |
| Agent and Rider configuration on the VM | `dotfiles/` |
| The Bitwarden register | `docs/manual-secrets.md` |

## What runs where

| On the VM | On the Mac |
|---|---|
| Rider backend, ReSharper, indexing | JetBrains Client rendering |
| `dotnet restore`, `build`, `test`, the debugger | keyboard, clipboard, notifications |
| Docker, the containers, the function hosts | browser, through forwarded ports |
| the frontend dev server | Bitwarden |
| `claude`, `codex`, git, every `ld-*` command | `ssh`, `tmux attach`, `vm-start`/`vm-stop`, the Terraform root |

## One VM at a time

There are two workstation VMs on `pve-2` and only one may run: 32 GB each plus the cluster guests
overcommits the node, and under memory pressure a guest OOM-kills its own build. From the Mac:

```bash
vm-start loady     # stops the other one first, then starts this one
vm-start dev       # the same, the other way round
vm-stop loady
vm-status
```

`vm-start` shuts the other machine down gracefully over ACPI and waits for it to actually stop.
It is clean, but a build running there is still lost, so it prints what it is stopping before it
does it. `--no-switch` refuses instead of switching. `ld-up` and `ld-down` are the same thing
without naming the VM.

Credentials come from `ld-tfin` if it has run in this shell, and from Bitwarden directly if not,
so these work as one-off commands anywhere.

## Streams

One worktree, one branch, one agent session:

```bash
ld-stn LOADY-15234-tender-notifications   # branch off origin/dev, create, enter
ld-stl                                     # what exists, and who holds the stack
ld-st LOADY-15234-tender-notifications     # enter an existing one
ld-str LOADY-15234-tender-notifications    # retire it
```

The branch name is validated against what the remote actually contains: `LOADY-<number>` with an
optional slug, on its own or behind `feature/`, `bugfix/` or `chore/`. `--any` is the escape hatch.

Three things follow from the machine:

1. **`loady-one` stays clean.** `git worktree add` writes only under `.git/worktrees/`, and the
   agent instruction files are symlinks into `loady-vm` covered by `.git/info/exclude`, which is
   local and never pushed. Nothing a teammate pulls changes.
2. **Only one stream runs the stack.** Every container pins a name and a host port and the function
   hosts bind fixed ports, so `ld-start` claims a `loadystack` slot and a second one is refused by
   name. That is an answer, not an obstacle: stop it there, or do work that does not need it.
   Builds, tests and Rider indexing run in as many worktrees as you like.
3. **The data is shared.** One SQL Server, one Cosmos emulator. A migration applied in one worktree
   is live in all of them, and `ld-reset` wipes the data for all of them. Migration work belongs in
   one worktree at a time.

`ld-str` refuses to remove a worktree holding uncommitted or unpushed work, because nothing here
commits automatically and the disk is the only copy.

## Running Loady

```bash
ld-reset            # recreate the containers from scratch (--hard also cleans the build)
ld-start            # containers, readiness, build, seed, the five default function hosts
ld-start --public   # and the six public ones
ld-fe               # the frontend dev server in local mode
ld-status           # every host, the containers, and who holds the slot
ld-logs Loady.Backend.Api
ld-stop
```

`ld-start` is the Linux equivalent of `backend/backend.ps1`, which is Windows-only where it matters
(`taskkill`, `Start-Process` into new windows, the Cosmos Emulator `.exe`). That file is not
modified and not used; `scripts/ld-dev.sh` and `compose/processes.json` replace it, starting the
same eleven hosts in the same order with the same pauses.

Migrations, replacing the old shell aliases:

```bash
ld-add AddTenderNotifications
ld-update
ld-remove
```

They pass the connection string as `-- --connection ...` rather than relying on the environment,
because `AppDbContextDesignFactory` reads the argument first and only that is guaranteed to be
present in an agent's non-interactive shell.

## Two Linux-only defects, and why the fixes exist

Both are invisible on macOS and Windows, and both break the same path: browser → frontend → `apim`
container → function host. Neither is fixed by editing `loady-one`.

1. **`backend/nginx.conf` proxies to `host.docker.internal`.** Docker Desktop invents that name;
   Docker Engine on Linux does not have it, and nginx fails to resolve it at startup. Fixed with
   `extra_hosts: host.docker.internal:host-gateway` on the `apim` service in
   `compose/loady-vm.yaml`. The `nginx.conf` itself is mounted read-only from the checkout, so the
   team's routing changes are picked up with nothing to maintain here.
2. **ufw's default deny drops the container's traffic back to the host.** nginx reaches the
   function hosts across the Docker bridge, which arrives inbound on a `br-*` interface. The
   symptom is a 502 with no other clue. `bootstrap.sh` allows inbound from `172.16.0.0/12` to
   exactly the ports in `compose/processes.json` — not a blanket rule, because the compose bridge
   is named dynamically and a blanket rule outlives its reason.

Related: the function hosts are started with `ASPNETCORE_URLS=http://0.0.0.0:<port>` so they listen
where nginx can reach them, and the Cosmos emulator's self-signed certificate is installed into the
system trust store, which on Windows and macOS the installer does and on Linux nothing does.

## Ports

All on the VM's loopback, and unreachable from the LAN: the Docker daemon publishes to `127.0.0.1`,
the compose file binds `127.0.0.1` explicitly, and ufw allows only SSH in. The Mac reaches them
through Rider's port forwarding or an SSH tunnel.

| Port | What | Forward |
|---|---|---|
| `8080` | frontend dev server | always |
| `7000` | APIM (nginx) — what the frontend calls | always |
| `7160`, `7296` | Backend and Events function hosts | always |
| `1433` | SQL Server | Mac-side database clients |
| `6379` | Redis | Mac-side clients |
| `8081`, `1234` | Cosmos emulator and its explorer | when inspecting documents |
| `10000`-`10002` | Azurite blob, queue, table | when using Azure Storage Explorer |
| `7001`, `7152`, `7094` | Backoffice, Loady2Go, Loady2Share | when working on those |
| `7247`-`7254` | the public APIs | when testing the public surface |

The first six are tracked in `dotfiles/rider/forwardedPorts.xml` and restored automatically. Add
others through Rider's Ports tool window; the change syncs back to that file.

Without Rider:

```bash
ssh -N -L 8080:localhost:8080 -L 7000:localhost:7000 -L 1433:localhost:1433 loady-vm
```

## Rider

JetBrains Client renders on the Mac; the backend, SDK, git, terminal, indexing, build, tests and
debugger run on the VM. No project files are mounted or synchronised to the Mac.

1. Toolbox → **Remote Development** → **SSH**, host `loady-vm` (the alias in `~/.ssh/config`, which
   carries the user and the key).
2. Project path `/home/dev/loady-one/backend/Loady.slnx`.
3. Connect; Gateway downloads the matching backend into the `dev` user's cache.
4. Apply the settings in `dotfiles/rider/README.md` — SSH agent forwarding **off** above all.

Git to Azure DevOps uses the VM's own key, bound per checkout with `core.sshCommand`, so nothing
prompts on the headless backend and Rider's credential-helper setting does not apply.

When Rider cannot connect, establish `ssh loady-vm true` first: Rider adds no independent access
path, so an SSH failure is fixed in the VM runbook rather than in the IDE.

## Access and boundaries

- **SSH** is keys only, no root, no passwords. The login is `dev@loady-vm`.
- **One door.** The Mac's key is the only way in: a lost or rotated key is a rebuild, because the
  `dev` user has no password for the Proxmox console, on purpose.
- **Firewall.** ufw denies incoming except SSH from the LAN subnet and the Docker bridge to the
  function-host ports. No router port-forward to the VM, ever.
- **Nothing listens on the LAN except sshd.**
- **Git is manual.** No script and no agent commits, pushes, merges or opens a pull request.
  `AGENTS.md` rule 2, enforced by the deny list in `dotfiles/ai/claude/settings.json`.
- **Company source on personal hardware.** Accepted deliberately, because the company machine
  cannot build this solution. The compensating controls are the boundaries above.
- **Sessions.** Long builds and agents run inside `tmux new -s loady`, so a Mac sleep or a Wi-Fi
  change does not kill them.

## The Mac's fallback checkout

`~/loady-one` on the Mac is kept for when the Proxmox host is down. It is **not** a second
workspace: nothing synchronises it with the VM, and Git remotes are the only transfer boundary. A
fallback session starts with a fetch and ends with a push. The Mac's toolchain is not maintained
for this solution, which is what keeps the arrangement honest.

## Backups and recovery

Git carries the work. Push before anything risky, and treat an unpushed branch as the only thing a
VM loss can cost — which under rule 2 is a real risk, so push at the end of a session.

The VM is disposable and has no Proxmox backup job: a rebuild is `ld-tfd`, which refuses while the
VM holds uncommitted or unpushed work in the checkout or any worktree. Take a snapshot by hand
before an Ubuntu release upgrade and delete it after validating; a snapshot is not a backup and
neither replaces Git.
