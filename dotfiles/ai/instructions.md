# Global agent instructions — Loady development VM

This is the machine-wide instruction file for Claude and Codex on `loady-vm`. It applies to every
repository on this machine. A repository's own `AGENTS.md` or `CLAUDE.md` is more specific and wins
where they differ.

The user is a senior developer with 15+ years of experience, working here as an employee on a team
codebase he does not own. Treat him as a peer: skip basics, be concise, challenge weak assumptions
with evidence.

## Git is manual. Always.

**Never commit, push, merge, rebase, cherry-pick, tag, stash, reset --hard, clean, or delete a
branch. Never open a pull request.** Not in `loady-one`, not in `loady-vm`, not anywhere on this
machine, whatever the task seems to need and however obvious it seems.

Work ends in the working tree. The founder reviews it and commits it himself, and the review is the
point: this is a shared repository, and a commit made by an agent is a commit nobody read.

When a task is finished, say what changed and offer a **short suggested commit message** as plain
text in the final message. That is the deliverable. Do not write it to a file, do not stage
anything, do not offer to commit it.

`git worktree add` creating a local branch is the one permitted git write, because it publishes
nothing. `ld-stn` is how it is done.

These prohibitions are also enforced in `~/.claude/settings.json`, so an attempt is refused rather
than trusted. The rule is here as well because being refused mid-task wastes the task.

## The machines

This VM holds the work. The Mac is a client: it renders Rider and a browser, and keeps a cold
fallback checkout for when this host is down. Everything about this machine — what it is, what is
installed, how it is rebuilt — is in `~/loady-vm`, which is a private repository. Nothing about it
belongs in `~/loady-one`, which the team owns.

`~/loady-one/backend/CLAUDE.md` is a symlink into `~/loady-vm/agents/`. Editing it through either
path is correct and lands in the private repository; that is deliberate.

## Working here

- **Scope.** Do the requested outcome and nothing else. The working tree is usually dirty, because
  nothing commits automatically — never treat that as something to clean up, and never touch paths
  outside the task.
- **Evidence.** Ground claims in the files and in real command output. Keep verified fact,
  inference and recommendation apart. Never invent a file, an output, an API behaviour or a
  completed action. Read the first real failure, not the last line.
- **Match the codebase.** Reuse the existing patterns, helpers and conventions of whatever project
  you are in. `~/loady-one/backend/CLAUDE.md` holds the backend's.
- **Verify.** `dotnet build` and the focused test for .NET, `yarn lint` for the frontend,
  `shellcheck` for shell. Say plainly what you did not run.
- **Commands.** `ld-start`, `ld-stop`, `ld-status`, `ld-logs`, `ld-reset`, `ld-build`, `ld-seed`,
  `ld-fe`, `ld-add`/`ld-update`/`ld-remove` for migrations, `ld-stn`/`ld-stl`/`ld-str` for
  worktrees. `~/loady-vm/README.md` has the table.
- **The stack runs in one worktree at a time.** A refusal from `ld-start` naming another worktree
  is the answer, not an obstacle: stop it there, or do work that does not need it.
- **One database.** There is a single SQL Server and a single Cosmos emulator on this machine, so a
  migration applied in one worktree is live in all of them.

## Writing

Lead with the outcome. Plain language, no preamble, no restatement of the request, no emoji, no
decorative symbols, no AI attribution anywhere — including in any commit message you suggest.
