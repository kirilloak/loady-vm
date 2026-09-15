# Result: archiving the checkout's plan files into this repository

Plan: [plans/2026_09_15_checkout_plans_archive.md](2026_09_15_checkout_plans_archive.md)

Status: complete. Nothing is committed; the working tree in `~/loady-vm` on the VM holds it all,
for the founder to review and commit (rule 2).

Founder decisions taken: both recommendations accepted. The archive lives under
`plans/`, and a worktree's plans are archived under `plans/worktrees/<name>/`.

## Files created or edited

- `scripts/sync-agent-files.sh` — third table `ARCHIVE_DIRS` (`backend/plans` and `infra/plans`),
  `ARCHIVE_ROOT`, `archive_dest`, `archive_dir`, `restore_checkout` and the `restore` subcommand;
  both archive directories added to the excludes and to the `managed` list the end-of-pass
  `git status` assertion covers; `backend/plans/` dropped from `EXTRA_EXCLUDES`, which now holds
  `.idea/` only, since the archive table excludes it; header and usage updated.
- `docs/remote-development.md` — new "Plans go one way" section under "How the sync works": the
  mapping table, checkout-always-wins, no deletion in either direction, and the restore command.
- `agents/backend/AGENTS.md` — the `## Plans` section now names `backend/plans/` and says the
  directory is invisible to `loady-one` and archived automatically.
- `agents/infra/AGENTS.md` — the same section, new; the file had none.
- `plans/` — the archive itself, created by the first pass: four files from the primary
  checkout (three under `backend/`, one under `infra/`).

No change to `infra/bootstrap.sh`, `scripts/loady-shell.zsh` or the crontab: the cron line, the
`install` subcommand and `ld-agents` already pass through, and `ld-agents restore` works because
the wrapper forwards its arguments.

## Manual actions for the founder

- Commit the working tree above, including the new `plans/` directory. Until that
  happens the archive exists on the VM only, which is the thing this change is meant to prevent.
- Pull on the Mac before touching its checkout; this was written on the VM (rule 5).

## Notes

- The layout changed after the plan was written and after the first commit: the archive was
  `plans/loady-one/<project>/` and is now `plans/<project>/`, with worktrees under
  `plans/worktrees/<name>/`. The plan text still describes the earlier shape. The founder also
  filed the finished plan pairs into `plans/done/`, which is where this file now lives.

- `~/loady-one/infra/plans/` was untracked and ignored by nothing when this started, so it was
  showing in that repository's `git status`. It is excluded now.
- Neither `backend/plans` nor `infra/plans` is tracked upstream: `git ls-files` returns nothing for
  either, so no teammate's file is at stake.
- `git status --porcelain -- <missing path>` exits 0, so a checkout without one of the two
  directories does not trip the assertion. Verified in an empty repository.

## Verification

All on the VM, against the real checkout unless stated.

- `bash -n scripts/sync-agent-files.sh`: clean.
- `shellcheck scripts/sync-agent-files.sh`: SC2034 (`LD_PROG`) and SC1091 (`lib.sh`) only, both
  present on `HEAD` before the change.
- First pass created `plans/{backend,infra}/` with the four existing plan files;
  `git -C ~/loady-one status --short` empty; `/infra/plans/` appended to `.git/info/exclude`.
- A new file in `backend/plans/` was archived on the next pass; editing it in the checkout
  re-archived it; editing the archived copy while the checkout still held the file was overwritten
  on the next pass; deleting it in the checkout left the archived copy in place. Probe file removed
  from both sides afterwards.
- A scratch checkout under a temporary `LOADY_WORKTREES` archived to
  `plans/worktrees/probewt/{backend,infra}/`, confirming the per-checkout keying. Removed
  afterwards.
- `restore` into an empty checkout wrote all four files into `backend/plans/` and `infra/plans/`;
  a second run wrote none and named all four as already there; `restore ~/loady-one` wrote none.
- Editing `agents/backend/AGENTS.md` and `agents/infra/AGENTS.md` here propagated to
  `~/loady-one/{backend,infra}/AGENTS.md` on the next pass, with `git status` there still empty.

Not run: nothing on the Mac, and no `--all` pass against a real `ld-stn` worktree — none exists
today, so the worktree path was exercised with a scratch checkout instead.
