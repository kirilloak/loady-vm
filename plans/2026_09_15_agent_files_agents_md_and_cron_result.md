# Result: agent instruction files as AGENTS.md, with a cron keeper

**Plan:** [plans/2026_09_15_agent_files_agents_md_and_cron.md](2026_09_15_agent_files_agents_md_and_cron.md)

**Status:** complete and live on the VM, with one design change the plan did not foresee. Claude does not follow an
`@AGENTS.md` import whose target resolves outside the project directory, so the checkout's
`CLAUDE.md` is a second name for `AGENTS.md` rather than a one-line pointer to it. Measured, not
inferred; the cases are below. Everything else landed as planned.

## Files created or edited

In this repository:

| File | Change |
|---|---|
| `agents/backend/AGENTS.md` | renamed from `agents/backend/CLAUDE.md`, content untouched |
| `agents/infrastructure/AGENTS.md` | renamed from `agents/infrastructure/CLAUDE.md`, content untouched |
| `agents/loady-one/AGENTS.md` | new; the checkout's own orientation, 45 lines |
| `scripts/link-agent-files.sh` | project table, both names per project, `--all`, `--quiet`, `install` |
| `infra/bootstrap.sh` | one line: `link-agent-files.sh install` beside the dotfiles one |
| `AGENTS.md` | rule 1 and the knowledge table |
| `README.md` | the `agents/` line and the `ld-agents` row |
| `dotfiles/README.md` | where project context comes from, beside the synced global pair |
| `dotfiles/ai/instructions.md` | the two sentences naming `backend/CLAUDE.md` |
| `plans/2026_09_15_agent_files_agents_md_and_cron_result.md` | this file |

Outside it, on the VM and on the Mac: the symlinks in each `loady-one` checkout, the entries in
each checkout's `.git/info/exclude`, one crontab line on the VM, and `~/.claude/CLAUDE.md` and
`~/.codex/AGENTS.md` refreshed by `dotfiles/sync.sh` from the edited `instructions.md`.

The pointer files `agents/*/CLAUDE.md` were created at step 1 and deleted again once the import
turned out not to resolve. They are in no commit.

## The deviation, and why

The plan had `CLAUDE.md` in the checkout be a symlink to a tracked one-line file containing
`@AGENTS.md`, with the "what could not be verified" section naming exactly this as the thing to
check. It does not work. Eight cases, `claude -p` on 2.1.272, each asking for a token that only the
instruction file carries:

| Case | Shape | Loaded |
|---|---|---|
| a, g | real `CLAUDE.md` with content | yes |
| b | real `CLAUDE.md` containing `@AGENTS.md`, real `AGENTS.md` beside it | yes |
| c | `CLAUDE.md` symlinked to a real file outside the tree | yes |
| d | `CLAUDE.md` symlinked to a file containing `@AGENTS.md` | no |
| f | the same, with `@./AGENTS.md` | no |
| i | real `CLAUDE.md` containing `@AGENTS.md`, `AGENTS.md` a symlink out of the tree | no |
| e, h | `@/absolute/path` import, from a symlink and from a real file alike | no |

The pattern the cases fit: a symlinked `CLAUDE.md` is followed wherever it points, but an `@` import
is only followed when its target is a real file inside the project directory. Every target here is
in `~/loady-vm`, so no arrangement of pointer plus symlink delivers the backend instructions to
Claude. Case b is why this repository's own root keeps working: both files are real and in-tree.

So `<checkout>/CLAUDE.md` and `<checkout>/AGENTS.md` are two symlinks to one
`agents/<project>/AGENTS.md`. The founder's first and third asks — one content file named
`AGENTS.md`, both tools loading it automatically — are met. The second, `CLAUDE.md` holding
`@AGENTS.md`, is met in `loady-vm` and cannot be met in `loady-one`. The alternative would be
copying the content into the team checkout as a real file, which rule 1 rules out.

## Manual actions for the founder

1. **Commit this file.** Everything else was committed and pushed as `937c0c9` and pulled on the
   VM; only this updated ledger is uncommitted. Suggested message: `Record the bootstrap re-run and
   the VM reconciliation`.

The earlier action, committing the work itself, is done.

## Notes

- The VM was down when the plan was written and for the first part of this session; it came up at
  07:57 and everything below ran on it.
- `ld-stn`'s branch validator accepts `feature/`, `bugfix/` and `chore/`, but the remote also
  carries `feat/`, `fix/` and `CGCEL-` branches, which need `--any`. `agents/loady-one/AGENTS.md`
  states this accurately rather than repeating the validator. Widening the validator is a
  follow-up, not part of this work.
- `frontend/CLAUDE.md` is a real file the team tracks. It is not in the project table, and the
  script refuses to replace a real file in any case; its checksum is unchanged.
- The Mac's fallback checkout was relinked too, because the rename left its old links dangling.
- **The two checkouts are reconciled.** The work was written on the Mac and rsynced to the VM so the
  VM could run and verify it; the founder then committed and pushed `937c0c9` from the Mac. The VM's
  redundant copies were removed after checking each one byte for byte against `origin/main`
  (`git hash-object` vs `git rev-parse origin/main:<path>`, all identical, and the two renamed-away
  `CLAUDE.md` files absent from `origin/main` too), and the checkout fast-forwarded `d99f86b..937c0c9`.
  Both trees are clean.
- **One cron failure, at 08:12:01, now fixed.** A `git restore` in the VM's checkout rolled
  `scripts/link-agent-files.sh` back to the pre-change version while the new crontab line was
  already installed, so cron called the old script with `--all` and it read that as a checkout path:
  `ld-agents: not a git checkout: --all`. One log line, no effect on the links. The pull put the new
  script back and the log has been silent since.

## Verification

Every command below was run and its result is what is recorded. Claude checks are `claude -p`
2.1.272 on the VM; Codex checks are `codex exec` 0.154.0.

| Check | Result |
|---|---|
| `shellcheck -x scripts/link-agent-files.sh infra/bootstrap.sh`, `bash -n` both | clean |
| Synthetic checkout on the Mac: first run, links, exclusions, `git status` | 6 links plus `backend/.run`, 8 exclusions, status empty |
| Same, second run | idempotent, no new exclusion lines, no relinks |
| Real-file guard: a real `infra/AGENTS.md` in a synthetic worktree | warned, file left byte-identical, `CLAUDE.md` still linked |
| `link-agent-files.sh` on `~/loady-one`, on the VM | 6 links plus `backend/.run`; `git status --porcelain` empty; `frontend/CLAUDE.md` md5 unchanged |
| `--all` with a worktree present and a non-checkout directory beside it | both checkouts linked, the non-checkout skipped, rc 0 |
| `--all --quiet`, twice | no output, rc 0 |
| `ld-agents --all` through the VM login shell | works |
| `install`, twice | installs once, says "already installed" the second time |
| Criterion 4: `rm ~/loady-one/infra/AGENTS.md` at 07:59:42 | relinked at 08:00:01 by cron; `journalctl -t loady-agents` shows exactly `linked infra/AGENTS.md`, one line |
| Criterion 5: journal over a quiet five minutes | no entries |
| Criterion 0, Claude, in `~/loady-one`, `backend/`, `infra/` | project headings `# loady-one`, `# Loady Backend`, `# Loady Infrastructure`; global `# Global agent instructions — Loady development VM` in all three |
| Criterion 0, Codex, same three directories | identical answers |
| `dotfiles/sync.sh` after editing `instructions.md`, then `--check` | wrote `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, no conflict |
| `git -C ~/loady-one status --porcelain`, VM and Mac, at the end | empty on both |
| `infra/setup.sh` — full bootstrap re-run on the VM, after the pull | exit 0, "Done in 288s: the VM matches this script"; the agent-files stage linked `~/loady-one` with the new script and both `install` calls reported "already installed" |
| `crontab -l` after that run | still exactly two lines, no duplicate |
| Criterion 0 re-checked after the bootstrap, Claude, three directories | project and global headings both present in all three |
| Criterion 0 re-checked after the bootstrap, Codex, three directories | the same; asked in `infra/` for a fact only that file carries, it answered `loadydevsa` for the qa state account and listed `~/.codex/AGENTS.md`, `~/loady-one/AGENTS.md`, `~/loady-one/backend/AGENTS.md` and `~/loady-one/infra/AGENTS.md` as its loaded documents |
| `git -C ~/loady-vm status --short` on the VM, at the end | empty, at `937c0c9` |

Not run:

- The worktree case of criterion 0 with a real agent session. No worktree exists, and creating one
  means creating a branch. `--all` was verified against a synthetic worktree instead, and the links
  it places there are the same links, from the same code path.
- `terraform` and the .NET build. Nothing in this change touches either.
