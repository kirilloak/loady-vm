``# loady-one

The Loady product repository. The team owns it; the founder is one developer on it.

This file holds the instructions and the `CLAUDE.md` beside it is one line, `@AGENTS.md`, which
imports it. Codex reads the first, Claude the second. Both are excluded locally, so they are
invisible to the repository and to everyone else working in it, and both are synced every minute
against `~/loady-vm/agents/loady-one/`. Editing either here is correct: the edit is carried back
into the private repository, under version control, where the founder commits it.

Nothing about the development machine, the VM, Rider, Docker, the `ld-*` commands or this setup
belongs in a file inside this checkout. That knowledge is in `~/loady-vm`, and
`~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` carry the part an agent needs.

## What is here

| Directory | What it is | Its own instructions |
|---|---|---|
| `backend/` | .NET Azure Functions, `Loady.slnx` | `backend/AGENTS.md`, the same arrangement |
| `infra/` | Terraform for every Azure environment | `infra/AGENTS.md`, the same arrangement |
| `frontend/` | The main Vue application | `frontend/CLAUDE.md`, the team's own file, tracked here |
| `backoffice/` | The admin .NET solution, `Loady.Backoffice.slnx` | none |
| `developer-portal/` | The public API catalogue and its nginx image | none |
| `loady2go/` | Loady2Go, the driver app, formerly DriverView | none |
| `loady2share/` | The sharing front end | none |
| `e2etests/` | Cypress suites against dev and QA | none |
| `pipelines/` | The Azure Pipelines definitions that tie them together | none |

A directory with no instruction file of its own is not undocumented: read its `README.md` and match
what the code already does.

## Frontend development

1. Use the Composition API with
   [`<script setup>`](https://vuejs.org/api/sfc-script-setup.html) for new Vue components and files.
2. Use the shared `ErrorMessage` component instead of custom error elements and CSS.
3. Add and preserve stable `data-qa-id` attributes on inputs, buttons and other elements used by
   integration tests, for example `data-qa-id="login-email-input"`.

## Working in more than one of them

A change that crosses `backend/` and `infra/` crosses two instruction files, and the one for the
directory you are editing wins for that edit. Pipelines under `pipelines/` and `*/pipelines/` run
from `$(Build.SourcesDirectory)` and name paths from the repository root, not from a project.

## Branches

`origin/HEAD` is `dev`, and that is what work branches from: `ld-stn <branch>` creates the worktree
off `origin/dev`. `main` feeds the `release/*` branches through
`pipelines/merge-main-into-release-branch.yml`.

Branch names are `LOADY-<number>-<slug>`, plain or behind a prefix. `ld-stn` validates
`feature/`, `bugfix/` and `chore/` without argument; the remote also carries `feat/`, `fix/` and
the occasional `CGCEL-` ticket, and those need `ld-stn <branch> --any`.

Nothing here commits, pushes, merges or opens a pull request. That rule is in `~/.codex/AGENTS.md`
and `~/.claude/CLAUDE.md`, and it has no exception in this repository.
