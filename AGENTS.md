# loady-vm

This repository is the whole of the Loady development setup that is not Loady's own source: the
Ubuntu VM that holds the checkout, everything installed inside it, the `ld-*` commands that drive
it, the agent instruction files, the Rider and agent configuration, and the documentation for all
of it.

It exists so that **nothing about this setup appears in the `loady-one` repository**, which is a
team repository the founder does not own.

## The five rules

Every decision in this repository follows from these. They are not preferences.

1. **`loady-one` is read-only to this setup.** No file is added, edited, committed or pushed
   there by anything here. The agent instruction files appear inside that checkout as symlinks
   into this repository (`scripts/link-agent-files.sh`), and `.idea/` is already covered by that
   repository's own `.gitignore`. `git status` in `loady-one` must always be empty of anything
   this setup created.

2. **Git is manual. No agent and no script commits, pushes, merges, rebases, opens a pull request
   or deletes a branch — in either repository, ever.** Work ends in the working tree. The founder
   reviews and commits it. An agent that has finished a task offers a short suggested commit
   message as plain text in its final message and stops there.

   This is not advisory. `dotfiles/ai/claude/settings.json` denies those commands at the harness
   level, so an agent that tries is refused rather than trusted. If a task seems to require a
   commit, it does not: say what is ready and stop.

   The single exception is `git worktree add` creating a local branch (`ld-stn`). It publishes
   nothing.

3. **Azure DevOps over SSH. No GitHub CLI.** Loady's remote is `git@ssh.dev.azure.com` and is
   reached only over SSH with the key the bootstrap places. `gh` is not installed and must not be
   installed or called; GitHub exists here only as the SSH remote of this repository itself. No
   Azure DevOps web UI or `az repos` automation either — pull requests are the founder's, by hand.

4. **The Mac is a client, plus a cold fallback.** Daily work happens on the VM. The Mac runs the
   Rider client, a browser, `ssh`, and the Terraform root in `infra`. Its `~/loady-one`
   checkout exists only for when the Proxmox host is down; nothing synchronises the two, and a
   fallback session starts with a fetch and ends with a push.

5. **The VM is disposable — its working tree is not.** Nothing on the VM's disk is authoritative
   except uncommitted and unpushed Git work, which under rule 2 is the normal state. Nothing here
   ever stashes, resets, cleans or force-checks-out a dirty tree. `ld-tfd` refuses to destroy the
   VM while any such work exists.

## Where knowledge lives

One fact, one file. Two files stating the same thing will disagree eventually.

| Knowledge | Owner |
|---|---|
| The VM: sizing, address, image, lifecycle | `infra/*.tf` and `infra/README.md` |
| What is installed and configured inside the VM | `infra/bootstrap.sh` |
| Converging the VM from the Mac | `infra/setup.sh` |
| Architecture, Rider, ports, boundaries, streams | `docs/remote-development.md` |
| The Bitwarden register and recovery | `docs/manual-secrets.md` |
| The `ld-*` command surface | `scripts/loady-shell.zsh` |
| Local services | `compose/loady-vm.yaml` |
| The function hosts and their ports | `compose/processes.json` |
| Agent and Rider configuration on the VM | `dotfiles/` and its `README.md` |
| Loady's own backend conventions | `agents/backend/CLAUDE.md` |
| Plans and their results | `plans/` |

Link between files with repository-root-relative paths.

## Plans

A change worth planning gets `plans/YYYY_MM_DD_<short_name>.md`: a one-sentence goal, observable
success criteria, real blockers, the approach with its tradeoffs, ordered steps each carrying what,
why, dependencies and verification, assumptions, risks, and any decision that needs the founder.
`None` for an empty section.

Each plan is paired with `plans/<plan_name>_result.md`, written before implementation starts and
updated at every material stop: the plan's path, status (complete, partial or blocked, with one
reason), every file created or edited, manual actions left for the founder, notes, and the exact
verification performed with its result. It is a ledger, not a cache: re-read and merge it before
each update, and never let it outrank live state.

Small work needs no plan. Work that turns out to need one stops and gets one.

## Working rules

**Scope.** Do the requested outcome and nothing else. Read the working tree freely; treat paths
outside the task as the founder's concurrent work and leave them alone. Never require a clean
working tree — under rule 2 it usually is not clean.

**Evidence.** Ground claims in the files, the live code and real command output. Keep verified
fact, inference and recommendation apart. Never invent a file, an output, an API behaviour or a
completed action. Read the first real failure, not the last line.

**Verification.** Match the check to the risk: `shellcheck` and `bash -n` for shell,
`terraform fmt -check` and `terraform validate` for Terraform, `docker compose config` for compose
files, `zsh -n` for the shell function file. Anything that touches the VM is verified on the VM.
State plainly what was not run.

**Writing.** Lead with the outcome. Plain language, no em dashes in commit messages, no decorative
symbols, no emoji, no preamble, no restatement of the request. Never add AI attribution anywhere.

**Shell.** No function in `scripts/loady-shell.zsh` may have a name beginning with an underscore:
an agent's shell snapshot drops those, and every command that calls one then fails with "command
not found". Prefix helpers `ld_`.

## Authorization

Everything in this repository targets the founder's own machines. There is no production here and
no deployed environment to protect, so there is no environment guard — the boundary that matters is
rule 2, and it is enforced by the Claude deny list rather than by prose.

Outside any agent's authority, in every case: committing or pushing anything, rotating or
disclosing a secret, destroying the VM without the founder asking for it, and anything at all in
the `loady-one` repository beyond reading it and editing files in its working tree.
