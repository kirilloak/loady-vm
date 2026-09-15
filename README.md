# loady-vm

The Loady development workstation: an Ubuntu Server VM on the founder's Proxmox host that holds the
`loady-one` checkout and runs the backend, the frontend, Docker, Rider's backend and the coding agents. The Mac is a
thin client — Rider's UI, a browser, a terminal.

Everything about the setup lives here, so that nothing about it lives in `loady-one`.

```
agents/          the Loady agent instruction files, synced into the checkout and its worktrees
compose/         local services and the function-host manifest
docs/            architecture, Rider, ports, boundaries, secrets
dotfiles/        agent and Rider configuration on the VM, with its own sync
infra/           Terraform for the VM, plus the bootstrap that builds its inside
plans/           plans and their result ledgers
scripts/         the ld-* commands
```

## Start here

- Building the machine for the first time: `infra/README.md`.
- How it all fits together, and how to connect Rider: `docs/remote-development.md`.
- The rules every agent working in this repository follows: `AGENTS.md`.

## Setting up the Mac

The VM itself is built by `infra/README.md`. What the Mac needs, once, so that `ssh loady-vm`,
`ld-vm`, `ld-vm-setup` and Rider all agree on how to reach it:

1. **The name.** The VM is on the LAN only, at a static address.

   ```bash
   grep -q ' loady-vm$' /etc/hosts || echo '192.168.1.51 loady-vm' | sudo tee -a /etc/hosts
   ```

2. **The SSH config.** `~/.ssh/config` is a symlink into the founder's settings repository
   (`settings/macos/dotfiles/.sshconfig`), so this is a tracked change there. Put the block
   **above** the `Host *` block, because SSH takes the first value it sees for each option:

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

   While there, pin the Azure DevOps key by hostname as well — `infra/README.md` says why.

3. **The commands**, by sourcing `scripts/loady-shell.zsh` as below.

Then `ssh loady-vm true` should succeed. If it does not, the VM is probably powered off: only one
workstation VM runs at a time, so `vm-loady` starts it and stops the other. That command lives in
the costfluent repository, which owns the Proxmox host. If it is running and still unreachable,
another LAN client has taken its address — `infra/README.md` has the check and the router
reservation that prevents it.

## Commands

`scripts/loady-shell.zsh` defines them; source it from `~/.zprofile` and `~/.zshrc`:

```zsh
[ -f "$HOME/loady-vm/scripts/loady-shell.zsh" ] && source "$HOME/loady-vm/scripts/loady-shell.zsh"
```

|                                                          |                                                                      |
|----------------------------------------------------------|----------------------------------------------------------------------|
| `ld-vm <cmd>`                                            | run a command on the VM, from the checkout                           |
| `ld-vm-setup`                                            | converge the VM (rerun the bootstrap)                                |
| `ld-tfin`                                                | load Terraform secrets and initialize the current root               |
| `ld-tfd [--force]`                                       | create or rebuild the VM end to end, including bootstrap and warm-up |
| `ld-reset [--hard]`                                      | recreate the containers and run both seeders                         |
| `ld-cosmos-cert [--print]`                               | trust the Cosmos emulator's certificate (`ld-reset` does it already) |
| `ld-add`, `ld-update`, `ld-remove`                       | EF migrations                                                        |
| `ld-stn`, `ld-st`, `ld-stl`, `ld-str`                    | worktrees                                                            |
| `ld-agents [--all]`                                      | sync the agent files into a checkout, or into every one of them      |

## One thing to know before using it

No script here commits or pushes anything, and neither may an agent. Work ends in the working tree and the founder
commits it. `AGENTS.md` rule 2 has the full statement and the reason.
