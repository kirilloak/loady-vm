# Global agent instructions — Loady development VM

This is the machine-wide instruction file for Claude and Codex on `loady-vm`. It applies to every
repository on this machine. A repository's own `AGENTS.md` or `CLAUDE.md` is more specific and wins
where they differ.

The user is a senior developer with 15+ years of experience, working here as an employee on a team
codebase he does not own. Treat him as a peer: skip basics, be concise, challenge weak assumptions
with evidence.

## Git is manual in loady-one

**In `~/loady-one` and its worktrees: never commit, push, merge, rebase, cherry-pick, tag, stash,
reset --hard, clean, or delete a branch, and never open a pull request** — whatever the task seems
to need and however obvious it seems.

Work ends in the working tree. The founder reviews it and commits it himself, and the review is the
point: that is a shared repository, and a commit made by an agent is a commit nobody read.

When a task is finished, say what changed and offer a **short suggested commit message** as plain
text in the final message. That is the deliverable. Do not write it to a file, do not stage
anything, do not offer to commit it.

`git worktree add` creating a local branch is the one permitted git write there, because it
publishes nothing. `ld-stn` is how it is done.

`~/loady-vm` is different: it is the founder's own repository and an agent may commit, push and
pull in it. Commit the task's paths by name rather than `git add -A`, never force-push, never
rewrite pushed history, and never add AI attribution to a message. Note that
`~/.claude/settings.json` still denies these commands everywhere, so the attempt is refused until
that list learns the difference; hand the commit to the founder when it is.

## The machines

This VM holds the work. The Mac is a client: it renders Rider and a browser, and keeps a cold
fallback checkout for when this host is down. Everything about this machine — what it is, what is
installed, how it is rebuilt — is in `~/loady-vm`, which is a private repository. Nothing about it
belongs in `~/loady-one`, which the team owns.

`~/loady-one` carries `AGENTS.md` and `CLAUDE.md` at its root, in `backend/` and in `infra/`.
`AGENTS.md` holds the instructions and `CLAUDE.md` is one line importing it, so Codex and Claude
read the same thing. Every one of them is synced both ways, every minute, against
`~/loady-vm/agents/`. Editing one where you find it is correct: the edit is carried into the
private repository for the founder to commit. Changing the same file on both sides between syncs
is a conflict, which writes nothing and says so.

## Working here

- **Scope.** Do the requested outcome and nothing else. The working tree is usually dirty, because
  nothing commits automatically — never treat that as something to clean up, and never touch paths
  outside the task.
- **Evidence.** Ground claims in the files and in real command output. Keep verified fact,
  inference and recommendation apart. Never invent a file, an output, an API behaviour or a
  completed action. Read the first real failure, not the last line.
- **Match the codebase.** Reuse the existing patterns, helpers and conventions of whatever project
  you are in. `~/loady-one/backend/AGENTS.md` holds the backend's and `~/loady-one/infra/AGENTS.md`
  the Terraform one; the checkout's own `AGENTS.md` says which other project has what.
- **Verify.** `dotnet build` and the focused test for .NET, `yarn lint` for the frontend,
  `shellcheck` for shell. Say plainly what you did not run.
- **Commands.** `ld-reset`, `ld-cosmos-cert`, `ld-add`/`ld-update`/`ld-remove` for migrations,
  `ld-stn`/`ld-stl`/`ld-str` for worktrees. Applications run through Rider's shared run
  configurations. `~/loady-vm/README.md` has the table.
- **The stack runs in one worktree at a time.** A refusal from `ld-reset` naming another worktree
  is the answer, not an obstacle: stop it there, or do work that does not need it.
- **One database.** There is a single SQL Server and a single Cosmos emulator on this machine, so a
  migration applied in one worktree is live in all of them.

## Writing

Lead with the outcome. Plain language, no preamble, no restatement of the request, no emoji, no
decorative symbols, no AI attribution anywhere — including in any commit message you suggest.
