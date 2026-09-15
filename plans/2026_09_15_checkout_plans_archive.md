# Archiving the checkout's plan files into this repository

## Goal

Plan files an agent writes under the `loady-one` checkout (`backend/plans/`, `infra/plans/`) are
invisible to that repository's git and version controlled in `loady-vm`, copied one way from the
checkout so that destroying the VM loses none of them.

## Success criteria

- `git status` in `~/loady-one` is empty of `backend/plans/` and `infra/plans/`, in the primary
  checkout and in every worktree.
- A file created or edited under either directory appears under `plans/loady-one/` in this
  repository within a minute, byte for byte, as an ordinary tracked-able file in the working tree.
- Nothing the archive holds is ever written back into the checkout by the periodic sync, and
  nothing in the checkout is ever deleted by it.
- Deleting a plan in the checkout leaves the archived copy in place.
- After a VM rebuild, one explicit command puts the archive back into a fresh checkout, and it
  refuses to overwrite a file that is already there.
- `shellcheck` and `bash -n` pass; the sync runs clean over the primary checkout and a worktree on
  the VM.

## Blockers

None.

## Approach

`scripts/sync-agent-files.sh` already walks the primary checkout and every worktree once a minute,
owns `.git/info/exclude` for the paths it manages, and asserts at the end that none of them show in
`git status`. The plans are the same problem with one direction removed, so they become a third
table in that script rather than a second script and a second crontab line.

Two-way sync is wrong here and state files are unnecessary. The checkout is where plans are written
and the archive is a copy of record: the checkout always wins, so a differing file is overwritten
in the archive with no conflict handling. The cost is that editing an archived plan in `loady-vm`
is pointless work that the next run undoes; that is documented, not defended against.

Deletion is not propagated. A plan removed in the checkout keeps its archived copy, which is what
"version controlled in case the VM is destroyed" means; the founder deletes an archived plan in
`loady-vm` when he wants it gone, and it stays gone unless the checkout still has it.

Restoring is therefore not automatic. If it were, a plan deleted in the checkout would reappear a
minute later. It is an explicit subcommand run once after a rebuild.

Worktrees each carry their own `backend/plans/`, so the archive is keyed by checkout rather than
flattened: the primary checkout owns `plans/loady-one/<project>/` and a worktree owns
`plans/loady-one/worktrees/<name>/<project>/`. No two sources can collide, and a removed worktree
leaves its plans behind, which is the point.

### Alternatives rejected

- A separate `scripts/sync-plans.sh` and a second crontab line: two schedulers, two copies of the
  checkout-walking and exclude logic, for forty lines of behaviour.
- Flattening every checkout into one archive directory: a worktree and the primary checkout writing
  the same dated file name silently overwrite each other.
- Two-way sync with state files, like the agent files: the archive has no author, so a conflict
  there has no meaning.

## Steps

1. **Exclude `infra/plans/` in the checkout.**
   *What:* add `infra/plans/` to `EXTRA_EXCLUDES` in `scripts/sync-agent-files.sh`.
   *Why:* it exists in `~/loady-one/infra/plans/` today, is untracked and is not ignored, so it is
   showing in `git status` right now. Rule 1 breach, independent of everything else here.
   *Dependencies:* none.
   *Verification:* `git -C ~/loady-one status --short` shows nothing under `infra/`.

2. **Add the archive table.**
   *What:* `ARCHIVE_DIRS` mapping a checkout-relative directory to its name under
   `plans/loady-one/`: `backend/plans|backend` and `infra/plans|infra`. Adding a third project is
   one line.
   *Why:* the two existing tables (`PROJECTS`, `DIR_PAIRS`) set the shape; a new direction needs a
   new table rather than a flag on an old one.
   *Dependencies:* 1.
   *Verification:* read.

3. **Implement `archive_dir`.**
   *What:* a one-way recursive copy of a checkout directory into its destination in this
   repository: every regular file, at any depth, written when it is missing or differs, using the
   existing `write_file` temp-and-rename; nothing deleted on either side; nothing written into the
   checkout. Destination resolved per checkout, primary against `plans/loady-one/<project>/` and a
   worktree against `plans/loady-one/worktrees/<name>/<project>/`. Each copy printed as `<-` the
   way `sync_one` prints its direction.
   *Why:* the archive is the whole feature.
   *Dependencies:* 2.
   *Verification:* step 8.

4. **Wire it into `sync_checkout`.**
   *What:* exclude each archive directory with `exclude_one` and add it to `managed` before the
   copies run, then call `archive_dir` per entry, skipping a checkout that has no such directory.
   *Why:* the final `git status` assertion is what guarantees rule 1, and a path outside `managed`
   is outside that guarantee.
   *Dependencies:* 3.
   *Verification:* step 8.

5. **Add the `restore` subcommand.**
   *What:* `sync-agent-files.sh restore [checkout]`, alongside the existing `install`: copies the
   archive for that checkout back into it, writing only files that do not exist, reporting each one
   written and each one skipped, and never running from cron.
   *Why:* a rebuilt VM has the archive and an empty checkout, and the periodic sync must not be the
   thing that puts files back.
   *Dependencies:* 3.
   *Verification:* step 8.

6. **Document it where the sync is documented.**
   *What:* the script's header comment gains the third table and the one-way rule; the sync section
   of [docs/remote-development.md](../docs/remote-development.md) gains what is archived, where it
   lands, that the checkout always wins, that deletion is not propagated, and the restore command.
   *Why:* one fact, one file.
   *Dependencies:* 5.
   *Verification:* read.

7. **Point the agent instructions at the archive.**
   *What:* one line in [agents/backend/AGENTS.md](../agents/backend/AGENTS.md) and
   [agents/infra/AGENTS.md](../agents/infra/AGENTS.md) saying plans live in that project's
   `plans/`, are invisible to the repository, and are archived automatically, so an agent neither
   commits them nor copies them anywhere.
   *Why:* those files are what an agent reads inside the checkout.
   *Dependencies:* 6.
   *Verification:* the sync copies the edit back out to the checkout; `git status` there stays
   empty.

8. **Verify on the VM.**
   *What:* `shellcheck scripts/sync-agent-files.sh`, `bash -n`; then, against a scratch checkout
   under the state directory as well as the real one: a new file is archived; an edited file is
   re-archived; a file deleted in the checkout keeps its archived copy; an archived file edited in
   `loady-vm` is overwritten on the next run; a worktree's plans land under `worktrees/<name>/`;
   `restore` into an empty checkout writes every file and into a populated one writes none;
   `git -C ~/loady-one status --short` is empty throughout.
   *Why:* the guarantee is about a repository the founder does not own.
   *Dependencies:* 7.
   *Verification:* the commands themselves, recorded in the result file.

## Assumptions

- `backend/plans/` and `infra/plans/` are the only plan directories in the checkout, and neither is
  tracked upstream. Verified: `git ls-files` returns nothing for either.
- Plan directories hold text files small enough that a per-minute byte comparison is free. They are
  36K and 4K today.
- The archive lives under `plans/` in this repository rather than a new top-level directory, so the
  founder's own plans and the checkout's sit in one place, separated by the `loady-one/` prefix.

## Risks

- **The archive grows and never shrinks.** Deletion is deliberate, so pruning it is the founder's,
  by hand, in this repository.
- **A worktree archive outlives the worktree.** Intended, and it means `ld-str` leaves a trail the
  founder has to clear.
- **An edit to an archived plan in `loady-vm` is silently undone** while the checkout still holds
  the file. Documented in step 6; the founder edits the checkout copy instead.
- **The `git status` assertion turns a missed exclude into a hard failure every minute.** Same
  behaviour as today, and preferable to silence.

## Open questions

- Destination layout: `plans/loady-one/backend/` as proposed, or a top-level `archive/` directory
  that keeps the founder's `plans/` listing short. Recommendation: as proposed.
- Whether a worktree's plans should be archived at all, or only the primary checkout's.
  Recommendation: archive them; a worktree is exactly the thing that disappears.
