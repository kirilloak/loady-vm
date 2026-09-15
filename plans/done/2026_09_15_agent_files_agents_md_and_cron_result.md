# Result: agent instructions synced into the checkout, from cron

**Plan:** [plans/2026_09_15_agent_files_agents_md_and_cron.md](2026_09_15_agent_files_agents_md_and_cron.md)

**Status:** complete and live on the VM. The plan's goal is met — Claude and Codex load the
machine-wide instructions and the instructions for the project they stand in, anywhere in
`loady-one` or a worktree, with no setup step. The mechanism is not the plan's: the files are real
and synced both ways rather than symlinked, and the script is `scripts/sync-agent-files.sh`. Both
changes are the founder's calls, made during the build, and both are recorded below.

## What is in place

| In this repository | In every checkout and worktree |
|---|---|
| `agents/loady-one/AGENTS.md` + `CLAUDE.md` | `AGENTS.md`, `CLAUDE.md` at the root |
| `agents/backend/` | `backend/AGENTS.md`, `backend/CLAUDE.md` |
| `agents/infra/` | `infra/AGENTS.md`, `infra/CLAUDE.md` |
| `dotfiles/rider/run/` | `backend/.run/`, file by file |

`AGENTS.md` holds the content, which Codex reads. `CLAUDE.md` is one line, `@AGENTS.md`, which
Claude follows. Real files, synced in both directions every minute by cron, with the three-way
conflict rule `dotfiles/sync.sh` already uses. No symlink anywhere.

## Files created or edited

| File | Change |
|---|---|
| `agents/backend/AGENTS.md` | renamed from `CLAUDE.md`, content untouched |
| `agents/infra/AGENTS.md` | renamed from `agents/infrastructure/CLAUDE.md`, content untouched, directory renamed to `infra` |
| `agents/loady-one/AGENTS.md` | new; the checkout's own orientation |
| `agents/*/CLAUDE.md` | new; one line, `@AGENTS.md` |
| `scripts/sync-agent-files.sh` | renamed from `link-agent-files.sh` and rewritten: project table, file and directory pairs, two-way sync with state, `--all`, `--quiet`, `install` |
| `infra/bootstrap.sh` | one line: `sync-agent-files.sh install` beside the dotfiles one |
| `scripts/ld-stream.sh`, `scripts/loady-shell.zsh` | the new script name |
| `AGENTS.md` | rule 1 rewritten for the sync; rule 2 split by repository; the knowledge table |
| `README.md` | the `agents/` line, the `ld-agents` row, the Git statement |
| `docs/remote-development.md` | new section "Agent instructions in the checkout": what is synced, why real files and not symlinks, how the sync works |
| `dotfiles/README.md`, `dotfiles/rider/README.md` | the new script, and a pointer to that section |
| `dotfiles/ai/instructions.md` | what the checkout carries, and the Git rule split by repository |

Outside this repository: the real files in each `loady-one` checkout on the VM and the Mac, the
entries in each checkout's `.git/info/exclude`, one crontab line on the VM, the sync state under
`~/.local/state/loady-vm/agents/`, and `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` refreshed by
`dotfiles/sync.sh`.

## The two deviations

**1. Symlinks do not work for this, which is why it is a sync.** The plan had the checkout's
`CLAUDE.md` be a symlink to a one-line `@AGENTS.md` pointer. It loads nothing. Eight cases,
`claude -p` on 2.1.272, each asking for a token only the instruction file carries:

| Case | Shape | Loaded |
|---|---|---|
| a, g | real `CLAUDE.md` with content | yes |
| b | real `CLAUDE.md` containing `@AGENTS.md`, real `AGENTS.md` beside it | yes |
| c | `CLAUDE.md` symlinked to a real file outside the tree | yes |
| d | `CLAUDE.md` symlinked to a file containing `@AGENTS.md` | no |
| f | the same, with `@./AGENTS.md` | no |
| i | real `CLAUDE.md` containing `@AGENTS.md`, `AGENTS.md` a symlink out of the tree | no |
| e, h | `@/absolute/path` import, from a symlink and from a real file alike | no |

A symlinked `CLAUDE.md` is followed wherever it points, but an `@` import is only followed when its
target is a real file inside the project directory — and a link into `~/loady-vm` always resolves
outside it. Case b is the one shape that works, and it needs both files real and in the checkout.

The founder's call, on that evidence: no symlinks at all, sync instead, in both directions, because
an agent may improve the backend conventions from inside `loady-one` and that edit has to come back
here. `backend/.run` followed for the same reason. The reasoning is now in
`docs/remote-development.md`, not only here.

**2. Git authority split by repository.** The founder authorized an agent to commit, push and pull
in `loady-vm` freely, `loady-one` unchanged. `AGENTS.md` rule 2, `README.md` and
`dotfiles/ai/instructions.md` say so now.

## Manual actions for the founder

1. **Commit what is in the tree.** Suggested message:

   ```
   Sync agent instructions into the checkout instead of linking them

   Claude does not follow an @AGENTS.md import whose target resolves outside
   the project directory, so the instruction files and the Rider run
   configurations are now real files kept equal to agents/ and
   dotfiles/rider/run by sync-agent-files.sh, in both directions, from a
   crontab line every minute. Split rule 2 so an agent may commit and push in
   this repository.
   ```

2. **Decide on the harness deny list.** `dotfiles/ai/claude/settings.json` denies `git commit`,
   `git push` and the rest for every repository, so rule 2's new second half is intent rather than
   capability: a Claude agent is still refused in `loady-vm`. The clean fix is a `PreToolUse` hook
   that allows the write only when the repository root is `~/loady-vm`, rather than deleting the
   deny entries, which would also unlock `loady-one`. Not done — it is a change to the guard that
   protects the team repository, and that is the founder's call.

## Notes

- `ld-stn`'s branch validator accepts `feature/`, `bugfix/` and `chore/`, but the remote also
  carries `feat/`, `fix/` and `CGCEL-` branches, which need `--any`. `agents/loady-one/AGENTS.md`
  states this accurately. Widening the validator is a follow-up, not part of this work.
- `frontend/CLAUDE.md` is a real file the team tracks. It is not in the project table, and the sync
  refuses a file that differs and has no sync history in any case.
- Two cron failures happened during the build, both understood and both over. At 08:12:01 a
  `git restore` in the VM's checkout rolled the script back to a version that did not know `--all`;
  at 08:25:01 the crontab still named `link-agent-files.sh` for the few seconds before `install`
  replaced the line. `install` now drops an entry under either name, so the rename cannot leave two.
- The VM's `~/loady-vm` was reconciled twice by checking each dirty path against `origin/main` with
  `git hash-object` before discarding it, then fast-forwarding.

## Verification

Claude checks are `claude -p` 2.1.272 on the VM, Codex checks `codex exec` 0.154.0.

| Check | Result |
|---|---|
| `shellcheck -x` and `bash -n` on `sync-agent-files.sh`, `ld-stream.sh`, `bootstrap.sh`; `zsh -n loady-shell.zsh` | clean |
| Synthetic checkout: first sync, with a leftover symlink and a real team file in place | symlink replaced by the real file; the team file refused with "no sync history"; everything else written; `git status` empty |
| Second run | idempotent, silent, no new exclusion lines |
| Edit in the checkout | copied back into this repository (`<- backend/AGENTS.md`) |
| Edit in this repository | copied out to the checkout (`-> infra/AGENTS.md`) |
| Both sides edited between passes | conflict: nothing written, both files intact, rc 1; resolved by copying one side over the other and rerunning |
| `backend/.run`: leftover symlink, then add in the checkout, add here, delete in the checkout | replaced by a real directory of 21 files; `<-` for the new one; `->` for the one added here; `x` removing it from both on delete |
| The same directions run live on the VM against `~/loady-one` | identical results; `~/loady-vm` showed the returning edit as a working-tree change, uncommitted |
| `--all --quiet`, twice | no output, rc 0 |
| `install`, with the old `link-agent-files.sh` line present | replaced it; `crontab -l` shows one agent line, plus the dotfiles line |
| `find ~/loady-one -maxdepth 3 -type l` | nothing; no symlink left |
| `git -C ~/loady-one status --porcelain`, VM and Mac | empty on both, before and after every run |
| Criterion 0, Claude, in `~/loady-one`, `backend/`, `infra/` | `# loady-one`, `# Loady Backend`, `Loady Infrastructure`, each with the global file — so the `@AGENTS.md` import resolves |
| Criterion 0, Codex, same three | the same; asked in `infra/` for a fact only that file carries it answered `loadydevsa` and listed all four loaded documents |
| `infra/setup.sh`, full bootstrap re-run, first pass | exit 0, "Done in 288s"; the agent-files stage ran the script and both `install` calls were idempotent |
| `dotfiles/sync.sh` after editing `instructions.md`, then `--check` | wrote `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, no conflict |

Not run:

- The worktree case with a real agent session. No worktree exists, and creating one means creating a
  branch. `--all` was verified against a synthetic worktree, through the same code path.
- `terraform` and the .NET build. Nothing here touches either.
