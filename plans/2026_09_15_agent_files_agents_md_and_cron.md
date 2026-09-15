# Agent instruction files: AGENTS.md as the source, CLAUDE.md as a pointer, cron as the keeper

## Goal

Claude and Codex, started anywhere in `loady-one` or in a worktree on the VM, load the machine-wide
instructions and the instructions for the project they are standing in, with no argument and no
setup step: every such directory carries `AGENTS.md` and `CLAUDE.md` as symlinks into
`~/loady-vm/agents/`, `AGENTS.md` holds the content, `CLAUDE.md` holds only `@AGENTS.md`, and cron
on the VM re-establishes the links every minute.

## What already works, and what does not

Global context is done and needs no new machinery. `dotfiles/sync.sh`'s manifest carries
`dotfiles/ai/instructions.md` to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, `infra/bootstrap.sh`
runs `sync.sh install` and a first sync on every converge, and the crontab line keeps both current.
Claude reads `~/.claude/CLAUDE.md` and Codex reads `~/.codex/AGENTS.md` on every session. This plan
verifies that, and changes none of it.

Project context is where the gaps are, and there are three:

1. **The checkout root carries nothing.** `~/loady-one` has no `AGENTS.md` and no `CLAUDE.md`, so a
   session started there — which is where `ld-vm` lands every command, `cd ~/loady-one` in
   `scripts/loady-shell.zsh:44` — loads global context and nothing else. Claude walks up from the
   working directory, Codex walks down from the Git root; neither finds a file at the root.
2. **`infra` carries nothing**, though `agents/infrastructure/CLAUDE.md` has held its instructions
   since the repository was created. It is stored and linked nowhere.
3. **Claude and Codex read different filenames**, and today both names in `backend` point at one
   file named `CLAUDE.md`. Splitting it into `AGENTS.md` plus a `CLAUDE.md` that imports it is what
   the founder asked for and what this repository's own root already does.

## Observable success criteria

0. The loading matrix, checked by hand once on the VM. For each of `~/loady-one`,
   `~/loady-one/backend`, `~/loady-one/infra` and a worktree: `claude` shows both the user memory
   and the project memory in `/context`, and `codex` lists both `~/.codex/AGENTS.md` and the
   directory's `AGENTS.md` among the documents it loaded. Eight sessions, all loading two files.
1. `ls -l ~/loady-one/{AGENTS.md,CLAUDE.md} ~/loady-one/backend/{AGENTS.md,CLAUDE.md}
   ~/loady-one/infra/{AGENTS.md,CLAUDE.md}` shows six symlinks into
   `~/loady-vm/agents/{loady-one,backend,infrastructure}/`.
2. `cat ~/loady-one/backend/CLAUDE.md` prints `@AGENTS.md` and nothing else; `cat
   ~/loady-one/backend/AGENTS.md` prints the backend instructions. Same pair under `infra/`.
3. `git -C ~/loady-one status --porcelain` is empty of every path this setup created, before and
   after the cron run (AGENTS.md rule 1).
4. `crontab -l` on the VM shows a `link-agent-files.sh` line beside the existing dotfiles line;
   `rm ~/loady-one/infra/AGENTS.md`, wait a minute, and the link is back, with the repair
   visible in `journalctl -t loady-agents`.
5. A steady state produces no journald output: at one pass a minute, cron only speaks when it
   changes or refuses something.
6. `~/loady-one/frontend/CLAUDE.md`, which is a real file the team owns, is byte-identical before
   and after.

## Non-goals

- Linking any project other than the checkout root, `backend` and `infra`. `frontend/CLAUDE.md` is tracked in
  `loady-one` and belongs to the team; `backoffice`, `developer-portal`, `e2etests`,
  `loady2go`, `loady2share`, `pipelines` have no instruction file here to link.
- Any change to how global context reaches the two tools. `dotfiles/sync.sh` and its manifest are
  already correct for both; this plan verifies them and leaves them alone.
- Syncing file *content* anywhere. There is one copy of each instruction file, in this repository,
  reached through symlinks. Nothing copies, and `dotfiles/sync.sh` is not involved.
- Anything on the Mac. Its `~/loady-one` is the cold fallback (rule 4); its links were placed by
  hand and stay as they are unless `ld-agents` is run there.
- Any Git operation in either repository (rule 2).

## Blockers

None.

## Current state, verified

| Fact | Evidence |
|---|---|
| `agents/backend/CLAUDE.md` and `agents/infrastructure/CLAUDE.md` are the only two instruction files | `ls agents/*/` |
| Only `backend` is linked; both names point at `agents/backend/CLAUDE.md` | `ls -l ~/loady-one/backend/*.md` on the VM |
| `agents/infrastructure/CLAUDE.md` is stored and linked nowhere | same; `~/loady-one/infra` has no `.md` instruction file |
| `loady-one/backend/.gitignore` ignores `.idea` only, not `CLAUDE.md`/`AGENTS.md` | `grep -n -i 'claude\|agents' backend/.gitignore` — one hit, `.idea` |
| The links stay invisible through `.git/info/exclude`, which already carries `/backend/CLAUDE.md`, `/backend/AGENTS.md`, `/backend/plans/` | `cat ~/loady-one/.git/info/exclude` |
| `loady-one/infra/.gitignore` ignores neither name | `cat infra/.gitignore` |
| `scripts/link-agent-files.sh` is called by `infra/bootstrap.sh:602`, by `scripts/ld-stream.sh:65` for each new worktree, and by `ld-agents` | those lines |
| The VM already runs one crontab line, `*/2 * * * * ~/loady-vm/dotfiles/sync.sh ... logger -t loady-dotfiles`, installed by `dotfiles/sync.sh install` from `infra/bootstrap.sh:604` | `crontab -l` on the VM; `dotfiles/sync.sh:185` |
| `~/loady-worktrees` is empty today | `ls -la ~/loady-worktrees` on the VM |
| This repository's own root already uses the pattern being asked for: `CLAUDE.md` contains `@AGENTS.md` | `cat CLAUDE.md` |
| Global context is already synced to both tools, and `~/loady-one` itself carries no instruction file | `dotfiles/sync.sh:36-38` manifest; `find ~/loady-one -maxdepth 2 -name 'AGENTS.md' -o -name 'CLAUDE.md'` returns `backend/{AGENTS,CLAUDE}.md` and the team's real `frontend/CLAUDE.md`, nothing at the root |
| `ld-vm` runs every command from `~/loady-one`, the directory with no project context | `scripts/loady-shell.zsh:44` |
| Codex is configured to read a project document up to 64 KiB, and the backend file is 45913 bytes | `dotfiles/ai/codex/config.toml` `project_doc_max_bytes`; `ls -l agents/backend/CLAUDE.md` |
| The VM was powered off while this plan was written | `ssh loady-vm` — connection refused. Nothing below was confirmed against live state this round; the live facts in this table are from the earlier session, when it was up. |

## Approach

Three changes, in one script and its callers.

**1. The files here become a content file and a pointer file, per project.**

```
agents/loady-one/AGENTS.md        <- new, short: the checkout's own orientation
agents/loady-one/CLAUDE.md        <- new, one line: @AGENTS.md
agents/backend/AGENTS.md          <- git mv from CLAUDE.md, content unchanged
agents/backend/CLAUDE.md          <- new, one line: @AGENTS.md
agents/infrastructure/AGENTS.md   <- git mv from CLAUDE.md, content unchanged
agents/infrastructure/CLAUDE.md   <- new, one line: @AGENTS.md
```

`agents/loady-one/AGENTS.md` is new and deliberately short, around twenty lines: which subproject
directory holds what, which of them have their own instruction file, and the one line about the
`backend/CLAUDE.md` symlink being intentional. It exists so that a session at the checkout root is
oriented rather than empty. It repeats nothing from `dotfiles/ai/instructions.md`, which is
machine-wide and already loaded beside it — the rules, the commands and the Git prohibition stay
there, one fact one file.

Both names are linked into the checkout, each to its namesake. Codex reads `AGENTS.md` and gets the
content directly; Claude reads `CLAUDE.md` and imports it. Whether Claude resolves `@AGENTS.md`
against the symlink's directory (`loady-one/backend`) or against its real path
(`loady-vm/agents/backend`), an `AGENTS.md` with the same content is there — which is the reason to
link both names rather than only `AGENTS.md`.

*Rejected:* keep one file and symlink `CLAUDE.md` to `AGENTS.md`. It loses the `@AGENTS.md` line the
founder asked for, and it makes the checkout carry a symlink to a symlink. *Rejected:* generate the
pointer file from the script instead of tracking it. Two lines of generation to avoid a two-line
tracked file, and the generated file would then be the one thing in the checkout not traceable to a
tracked source.

**2. `scripts/link-agent-files.sh` gains a project table, a `--all` mode and a `--quiet` mode.**

The table is the whole of the per-project knowledge:

```bash
# <directory under agents/> | <directory under the checkout>
PROJECTS=( "loady-one|." "backend|backend" "infrastructure|infra" )
```

For each entry the script links `<project>/AGENTS.md` and `<project>/CLAUDE.md`, and excludes both
paths when the checkout does not ignore them. The `.` entry needs the exclusion paths written as
`/AGENTS.md` and `/CLAUDE.md`, not `/./AGENTS.md`: `.git/info/exclude` patterns are matched as
written, so a normalisation step is required rather than string concatenation. `backend/.run -> dotfiles/rider/run` stays exactly as
it is, backend-only, outside the loop. `link_one`'s refusal to replace a real file is what protects
`frontend/CLAUDE.md` and anything a teammate adds later; it stays.

`--all` enumerates `$LOADY_REPO` plus every directory in `$LOADY_WORKTREES`, links each, and returns
non-zero if any one failed. `--quiet` suppresses the per-checkout success line and the "linked"
lines for links that were already correct, leaving only repairs, warnings and failures — so cron's
steady state is silent.

*Rejected:* a second script for the cron pass. The enumeration is four lines around the function
that already exists.

**3. `install` puts the cron line on the VM, `infra/bootstrap.sh` calls it.**

Copied in shape from `dotfiles/sync.sh:185`, including the idempotence check and the `logger` tag:

```
* * * * * $VM_REPO/scripts/link-agent-files.sh --all --quiet 2>&1 | /usr/bin/logger -t loady-agents
```

Every minute, which is cron's floor and tighter than the dotfiles line's two. The pass is cheap when
nothing is wrong: per checkout it is a `readlink` per link, a `grep` over `.git/info/exclude` and one
`git status --porcelain` limited to the four link paths, with `git check-ignore` reached only for a
path the checkout does not already exclude. Nothing is written and nothing is printed in the steady
state (`--quiet`), so a minute costs a few milliseconds of disk cache and no journald lines. The
existing callers — bootstrap, `ld-stn`, `ld-agents` — still place links at the moment they are needed; cron
is the net under a checkout re-cloned by hand, a link deleted by a tool, or a worktree made outside
`ld-stn`.

*Rejected:* a systemd user timer. It needs lingering enabled to survive logout, and the machine
already has exactly one scheduling mechanism with one installer pattern.

## Ordered steps

Each step leaves the repository working and verifiable.

### 1. Split each instruction file into content and pointer, and write the root one

**What.** `git mv agents/backend/CLAUDE.md agents/backend/AGENTS.md`, same for
`agents/infrastructure`, then write `agents/<project>/CLAUDE.md` containing the single line
`@AGENTS.md`. Then write `agents/loady-one/AGENTS.md` and its pointer.

**Why.** The content file is `AGENTS.md`; `CLAUDE.md` imports it, matching this repository's root.

**Dependencies.** None.

**Verification.** `git status --short` shows two renames and four new files and nothing else;
`git diff -M --stat` shows the renames as pure renames (100% similarity);
`cat agents/*/CLAUDE.md` prints `@AGENTS.md` three times.

**Note.** The checkout's existing `backend/CLAUDE.md` and `backend/AGENTS.md` symlinks point at
`agents/backend/CLAUDE.md`, which after this step is the pointer rather than the content. Both are
relinked in step 2; between the two steps an agent reading `backend/AGENTS.md` sees `@AGENTS.md`
instead of the instructions. Do not stop between these two steps.

### 2. Teach `scripts/link-agent-files.sh` the project table

**What.** In `scripts/link-agent-files.sh`: replace the single `AGENT_FILE` with the `PROJECTS`
table; loop the existence check, the exclusion loop and `link_one` over it, linking
`agents/<project>/AGENTS.md -> <dir>/AGENTS.md` and `agents/<project>/CLAUDE.md -> <dir>/CLAUDE.md`;
keep `backend/.run` and `backend/plans/` and `.idea/` as they are; extend the final
`git status --porcelain` assertion to every path the run touched rather than the three named ones.
Rewrite the header comment, which currently describes one file under two names.

**Why.** `infra` needs the same treatment `backend` has, and a table is what makes a third project
one line rather than a second copy of the block.

**Dependencies.** Step 1.

**Verification.** `shellcheck scripts/link-agent-files.sh` and `bash -n`. Then on the VM, against a
throwaway clone so a failure costs nothing:

```bash
git clone --no-checkout ~/loady-one /tmp/t && git -C /tmp/t checkout dev   # or: cp -a of the real one
~/loady-vm/scripts/link-agent-files.sh /tmp/t
ls -l /tmp/t/{backend,infra}/{AGENTS.md,CLAUDE.md} /tmp/t/backend/.run
git -C /tmp/t status --porcelain          # empty
grep -c . /tmp/t/.git/info/exclude        # infra entries present, no duplicates
~/loady-vm/scripts/link-agent-files.sh /tmp/t   # second run: idempotent, no new exclude lines
printf 'teammate file\n' > /tmp/t/infra/AGENTS.md.real && mv /tmp/t/infra/AGENTS.md{.real,} 2>/dev/null
```

Last two lines are the guard test: with a real file in place the script must warn and leave it,
not replace it. Repeat that case for `frontend/CLAUDE.md`, which is real in the actual checkout.

### 3. Run it against the real checkout on the VM

**What.** `~/loady-vm/scripts/link-agent-files.sh` with no argument, on the VM.

**Why.** It is the live state the founder works in; steps 1 and 2 leave it holding stale links.

**Dependencies.** Step 2. The repository must be present on the VM at the new revision — this
repository is not committed by an agent (rule 2), so either the founder commits and pulls, or the
run happens from an edited working tree on the VM. Say which before starting.

**Verification.** Success criteria 1, 2, 3 and 6, by hand. Then criterion 0, the loading matrix:
this is the step where the whole point of the work is either true or not, and it is checked with
real sessions rather than inferred from the file layout. `claude` in each of the four directories,
`/context`, both memories listed; `codex` in each, its startup listing naming both documents.

### 4. Add `--all`, `--quiet` and `install`

**What.** In the same script: argument parsing for the three, the checkout enumeration for `--all`
(`$LOADY_REPO` plus `$LOADY_WORKTREES/*`, skipping a path that is not a checkout), the output
suppression for `--quiet`, and the `install` branch writing the crontab line.

**Why.** The cron pass the founder asked for, and a steady state that does not fill journald.

**Dependencies.** Step 2.

**Verification.** `shellcheck`; `bash -n`; on the VM `link-agent-files.sh --all` (with a scratch
worktree present, created by `ld-stn` and removed by `ld-str` afterwards) and `--all --quiet`
twice, the second printing nothing.

### 5. Install the cron line, on the VM and in the bootstrap

**What.** `~/loady-vm/scripts/link-agent-files.sh install` on the VM, and a call to it in
`infra/bootstrap.sh` beside the existing `dotfiles/sync.sh install` at line 604.

**Why.** The line has to exist on the machine that is running now, and on every machine built after
this.

**Dependencies.** Step 4.

**Verification.** `crontab -l` shows both lines; `install` a second time says it is already there
and does not duplicate; `shellcheck infra/bootstrap.sh`; then criterion 4 end to end — delete
`~/loady-one/infra/AGENTS.md`, wait out the interval, confirm the link returns and
`journalctl -t loady-agents --since '-15 min'` shows exactly the repair.

### 6. Documentation, one fact one file

**What.**

- `dotfiles/README.md` "What is synced" — the global pair is already described; check it still reads
  correctly beside the new project links, and say where project context comes from, since that table
  is the first place anyone looks for "what does an agent load here".

- `AGENTS.md:80` — "Loady's own backend conventions" now points at `agents/backend/AGENTS.md`.
  Add a row for `agents/infrastructure/AGENTS.md`.
- `AGENTS.md:17` — rule 1's parenthetical still describes `scripts/link-agent-files.sh` correctly;
  check the wording covers `infra` as well as `backend`.
- `README.md:10` — the `agents/` line, and the `ld-agents` row in the command table, mention the two
  projects and the cron pass.
- `dotfiles/ai/instructions.md:37` and `:48` — the two sentences naming
  `~/loady-one/backend/CLAUDE.md`. These are the machine-wide instructions every agent on the VM
  reads; they must describe the new pair, and name `infra` as having one too.
- `dotfiles/README.md:78-83` and `docs/remote-development.md:95` — both name
  `scripts/link-agent-files.sh` for `backend/.run`; unchanged in substance, checked for accuracy.
- `infra/README.md` — whether its bootstrap description needs the new cron line; only if it already
  lists the dotfiles one.

**Why.** Five files name this script or these paths. One left stale is the next agent's wrong turn.

**Dependencies.** Steps 1 to 5.

**Verification.** `grep -rn 'agents/backend/CLAUDE.md\|agents/infrastructure/CLAUDE.md' --exclude-dir=.git --exclude-dir=plans .`
returns nothing outside `plans/`, which is a historical record and stays as written.

### 7. Result ledger

**What.** `plans/2026_09_15_agent_files_agents_md_and_cron_result.md`, per AGENTS.md: created
before step 1 runs and updated at every material stop.

**Why.** Repository convention.

## Files this work owns

Another agent should stay out of these until it is done:

```
agents/loady-one/AGENTS.md          (new)
agents/loady-one/CLAUDE.md          (new)
agents/backend/AGENTS.md            (renamed from CLAUDE.md)
agents/backend/CLAUDE.md            (replaced with the pointer)
agents/infrastructure/AGENTS.md     (renamed from CLAUDE.md)
agents/infrastructure/CLAUDE.md     (replaced with the pointer)
scripts/link-agent-files.sh
infra/bootstrap.sh                  (one call, beside line 604)
AGENTS.md, README.md, dotfiles/README.md, dotfiles/ai/instructions.md   (the lines in step 6)
plans/2026_09_15_agent_files_agents_md_and_cron.md
plans/2026_09_15_agent_files_agents_md_and_cron_result.md
```

Untouched, deliberately: `dotfiles/sync.sh` and its manifest, `scripts/ld-stream.sh` (it already
calls the linker and needs no change), everything in `loady-one` other than the four symlinks and
`.git/info/exclude`.

## Assumptions

1. "All of them synced via cron" means the symlinks are re-established on a schedule, not that file
   content is copied anywhere. There is one copy of each instruction file and it lives here.
2. `agents/infrastructure` maps to `loady-one/infra`. Nothing in the repository states this; it is
   inferred from the file's content, which is the Terraform IaC for Loady on Azure, and from
   `loady-one/infra` being the only Terraform directory in the checkout.
3. One minute is the interval, as asked. It is cron's floor; anything tighter needs a systemd
   timer, which this machine does not use.
4. Claude loads a project `CLAUDE.md` reached through a symlink and follows its `@AGENTS.md`
   import; Codex loads a symlinked `AGENTS.md`. Both are how the `backend` pair works today, minus
   the import. Criterion 0 is what turns this from assumption into fact, and it is cheap.
5. A short root `AGENTS.md` is wanted at all. The alternative is to accept that a session at
   `~/loady-one` has only machine-wide context and must `cd` into a project — which contradicts
   "automatically" as asked.
6. The founder will commit and pull this repository on the VM, or accept that steps 3 and 5 run from
   an uncommitted working tree there. No agent commits either repository (rule 2).

## What could not be verified

- That Claude Code resolves `@AGENTS.md` from a `CLAUDE.md` reached through a symlink in the way
  described. Both candidate resolutions land on an identical file, so the design does not depend on
  the answer — but step 3 should confirm it once, by opening an agent session in
  `~/loady-one/backend` and checking the instructions are actually loaded, not just the pointer
  line.
- Whether any teammate tooling in `loady-one` reads `infra/AGENTS.md` or would be confused by an
  untracked symlink there. `git status` staying clean is the only contract this setup has, and
  step 2 asserts it.

## Risks

| Risk | Mitigation |
|---|---|
| A cron pass writes into `loady-one` and a teammate sees it | The script's closing `git status --porcelain` assertion fails loudly rather than silently leaving a change; extend it to every path touched (step 2). Criterion 3 checks it after a real cron run. |
| The window between steps 1 and 2, where the checkout's links point at the pointer file | Named in step 1; do the two together. |
| Cron noise in journald | `--quiet`; criterion 5. |
| The team adds a real `AGENTS.md` at the `loady-one` root | `link_one` warns and leaves it, so the root link is simply not made; the warning is in `journalctl -t loady-agents`. That file would then be the team's project context and this setup's root file becomes redundant — a decision for then, not a failure. |
| A real `infra/AGENTS.md` appears in `loady-one` later, from the team | `link_one` warns and leaves it; the link is simply not made and the warning shows up in `journalctl -t loady-agents`. |
| `.git/info/exclude` accumulating duplicate lines at a pass a minute | The existing `grep -qxF` guard; verified by the second-run check in step 2. |

## Decisions needed from the founder

1. **How steps 3 and 5 reach the VM.** Commit and pull, or run from the VM's working tree. Both are
   the founder's action under rule 2.
2. **The root file's content.** Twenty lines of orientation is the proposal. If it should carry
   more — the branch convention, the pipeline layout — say so and it goes in at step 1 rather than
   growing later.
3. **Anything beyond the root, `backend` and `infra`?** `frontend/CLAUDE.md` exists in `loady-one` as a real,
   team-owned file. Bringing it under this setup would mean deleting a file from a repository the
   founder does not own — out of scope here, and worth a separate decision if it is wanted.
