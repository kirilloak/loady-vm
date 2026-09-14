# loady-vm

The Loady development workstation: an Ubuntu Server VM on the founder's Proxmox host that holds the
`loady-one` checkout and runs the backend, the frontend, Docker, Rider's backend and the coding
agents. The Mac is a thin client — Rider's UI, a browser, a terminal.

Everything about the setup lives here, so that nothing about it lives in `loady-one`.

```
agents/          the Loady agent instruction files, symlinked into the checkout
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

## Commands

`scripts/loady-shell.zsh` defines them; source it from `~/.zprofile` and `~/.zshrc`:

```zsh
[ -f "$HOME/loady-vm/scripts/loady-shell.zsh" ] && source "$HOME/loady-vm/scripts/loady-shell.zsh"
```

| | |
|---|---|
| `ld-vm <cmd>` | run a command on the VM, from the checkout |
| `ld-vm-setup` | converge the VM (rerun the bootstrap) |
| `ld-up [--takeover]`, `ld-down` | power the VM on and off |
| `ld-tfin` | load Terraform secrets and initialize the current root |
| `ld-tfd [--force]` | create or rebuild the VM end to end, including bootstrap and warm-up |
| `ld-start [--public]`, `ld-stop`, `ld-status`, `ld-logs` | the function hosts and containers |
| `ld-reset [--hard]` | recreate the containers from scratch |
| `ld-build`, `ld-seed`, `ld-fe` | build, seed, frontend dev server |
| `ld-add`, `ld-update`, `ld-remove` | EF migrations |
| `ld-stn`, `ld-st`, `ld-stl`, `ld-str` | worktrees |
| `ld-agents` | link the agent instruction files into a checkout |

## One thing to know before using it

No script here commits or pushes anything, and neither may an agent. Work ends in the working tree
and the founder commits it. `AGENTS.md` rule 2 has the full statement and the reason.
