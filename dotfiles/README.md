# dotfiles

The agent and Rider configuration on the development VM, with one sync script that keeps each
tracked file here equal to its live counterpart.

## What is synced

`sync.sh` holds the manifest; this table mirrors it for reading.

| Repository file | Live file |
|---|---|
| `ai/instructions.md` | `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` |
| `ai/claude/settings.json` | `~/.claude/settings.json` |
| `ai/claude/mcp.json` | the `mcpServers.rider` entry in `~/.claude.json` |
| `ai/codex/config.toml` | `~/.codex/config.toml` |
| `rider/forwardedPorts.xml` | `backend/.idea/.idea.Loady/.idea/forwardedPorts.xml` in the checkout |
| `rider/indexLayout.xml` | the same directory |

Never synced: `auth.json`, sessions, history, memories, plugins, and anything under
`~/.claude/projects`.

That table is the machine-wide context both tools load on every session. Project context is a
different script with the same conflict rule: `scripts/sync-agent-files.sh` keeps the instruction
files in `~/loady-one` equal to `agents/` in this repository.
[docs/remote-development.md](../docs/remote-development.md#agent-instructions-in-the-checkout) says
why it copies rather than links, and how.

## The VM only

This runs on the VM and nowhere else. The Mac's `~/.claude` is owned and synced by a different
repository; a second sync managing the same live file would conflict on every edit, and the loser
would be whichever ran last. The VM has no other manager, which is what makes it safe here.

The trigger is one crontab line every two minutes, installed by `sync.sh install` and logged to
journald (`journalctl -t loady-dotfiles`). `infra/bootstrap.sh` runs `install` and a first
sync on every converge, so a rebuilt VM has these files as soon as its checkout exists.

## How the sync works

Either side may be edited. The content each pair was last synced to is kept under
`~/.local/state/loady-vm/dotfiles/`, so:

- a change on one side is copied to the other;
- a change on **both** sides since the last sync is a conflict: nothing is written, the pair is
  named in `.../dotfiles/CONFLICT`, and a Claude session prints it on start. Resolve by copying the
  side you want over the other; the next sync sees them equal and clears the marker;
- a pair with no history lets the more recently written side win, which happens once per pair.

Claude's `~/.claude.json` also holds machine-local state, so it is the exception: the sync merges
the tracked `mcpServers.rider` entry into that file and leaves every other key untouched.

Writes are temp-and-rename and mode 0600. The script never runs git: a change that lands here is a
working-tree change to commit (`AGENTS.md` rule 2).

## The Claude settings are load-bearing

`ai/claude/settings.json` is where rule 2 stops being prose. Claude runs with
`--dangerously-skip-permissions`, so an allow list approves nothing that would have been asked
about anyway — but **deny rules still apply in that mode**. The deny list holds every git write
that publishes or destroys: commit, push, merge, rebase, cherry-pick, revert, tag, stash,
`reset --hard`, `clean`, branch deletion. Plus `gh` and `az repos`, which have no business on this
machine at all (`AGENTS.md` rule 3).

`git worktree add` is deliberately not denied: it creates a local branch and publishes nothing, and
it is how `ld-stn` works.

## Rider

The forwarded ports are the reason this folder exists. In SSH remote-development mode the mapping
lives in the project's `.idea` directory on the VM, which is disposable: it is gone after a rebuild
and absent in every new worktree. Tracking the file makes the set reproducible; `ld-stn` seeds it
into each new worktree with `sync.sh --seed-worktree`.

Tracked entries are the always-on set: `8080` (frontend), `7000` (APIM), `7160` and `7296` (the two
default function hosts), plus `1433` and `6379` for Mac-side database clients. Add the rest from
the port table in `docs/remote-development.md` through Rider's Ports tool window when you need them;
the change syncs back here.

`rider/README.md` holds the settings a project file cannot carry.

## Rider run configurations

`rider/run/*.run.xml` holds the application run configurations shared by every checkout and
worktree. `scripts/sync-agent-files.sh` syncs that directory into each checkout at `backend/.run`,
file by file and in both directions, and adds a local Git exclusion when needed. A configuration
Rider writes there is carried back into this repository; a new one added here appears in every
checkout on the next pass, and one deleted on either side goes from both. These files do not pass
through `sync.sh`.

Run `ld-agents` in an existing checkout to sync it now. `ld-stn` does this automatically for a new
worktree, and a crontab line does it every minute.

## Manual configuration

In Rider, enable the MCP server and expose only the router:

1. Open **Tools > MCP Server** and select **Enable MCP Server**.
2. Open **Tools > MCP Server > Exposed Tools** and select **Enable Router Only Mode**.

## Verifying a change

```bash
shellcheck dotfiles/sync.sh
DOTFILES_HOME=/tmp/t/home DOTFILES_REPO_ROOT=/tmp/t/repo DOTFILES_STATE=/tmp/t/state dotfiles/sync.sh
```

Point all three at scratch directories and walk the cases: no history, a change on each side, a
change on both. Nothing in the real home is touched.
