# Result: Rider run configurations for the VM

Plan: [2026_09_14_rider_run_configurations.md](2026_09_14_rider_run_configurations.md)

Status: **partial** — the repository implementation is complete, the configurations are linked and
loaded by Rider, and all non-interactive checks pass. Live Azure Functions launches are blocked
until Rider's IDE-global Core Tools executable is set to the npm installation path; the end-to-end
frontend, breakpoint and B2C checks remain manual after that.

## Verification performed

Recorded as it happens. `not run` means not run, not "assumed fine".

| Check | Result |
|---|---|
| `scripts/link-agent-files.sh /home/dev/loady-one`, twice | Passed; `backend/.run` points to `dotfiles/rider/run`, `/backend/.run` occurs once in `.git/info/exclude`, and `loady-one` remains clean |
| Rider `get_run_configurations` | Passed; all 21 shared configurations are loaded with the expected Azure Functions, npm, .NET project and compound types |
| Host names, ports and project paths against `compose/processes.json` and `loady-one` | Passed for all 11 hosts |
| Forwarded-port keys against the documented service and host set | Passed; 20 unique ports |
| Tracked configuration secret scan | Passed; no B2C client secret, SendGrid key or non-local password found |
| `dotnet build Loady.slnx --nologo --verbosity minimal` | Passed; 0 warnings and 0 errors |
| `shellcheck scripts/*.sh infra/bootstrap.sh infra/run-bootstrap.sh infra/setup.sh` | Passed |
| `bash -n scripts/*.sh infra/bootstrap.sh infra/run-bootstrap.sh infra/setup.sh` | Passed |
| `zsh -n scripts/loady-shell.zsh` | Passed |
| `jq empty compose/processes.json` | Passed |
| `docker compose ... config --quiet` with `LOADY_REPO_DIR=/home/dev/loady-one` | Passed |
| Fresh login-shell command surface | Passed; retained commands resolve and all eight retired application commands do not |
| `dotfiles/sync.sh --check` | Passed |
| XML loading | Passed through Rider for all 21 run configurations; `xmllint` is not installed on the VM, so the plan's separate `xmllint --noout` command was not run |
| `all-backend` launch through Rider | Blocked before host startup; builds passed, then Rider logged that it could not find v4 Core Tools under its download directory. `/usr/lib/node_modules/azure-functions-core-tools/bin/func` exists and reports 4.14.0; the required Rider setting is documented in `dotfiles/rider/README.md` |

## Files created or edited

| File | Change |
|---|---|
| `dotfiles/rider/run/*.run.xml` | Added 11 local hosts, the SSO host, four frontend modes, two seeders and three compounds (21 files) |
| `dotfiles/rider/forwardedPorts.xml` | Added the complete 20-port forwarding set |
| `scripts/link-agent-files.sh` | Links `backend/.run`, adds a local exclusion and asserts the checkout stays clean |
| `scripts/ld-reset.sh` | Reduced the stack command to backing-service reset, readiness and Cosmos trust |
| `scripts/ld-dev.sh` | Removed the retired application process manager |
| `scripts/loady-shell.zsh` | Removed the eight retired application commands and retained `ld-reset` |
| `scripts/ld-stream.sh`, `scripts/slot.sh`, `scripts/lib.sh`, `scripts/cosmos-cert.sh` | Updated worktree, slot and command behaviour/comments for Rider ownership |
| `compose/processes.json`, `compose/loady-vm.yaml` | Retained the host/port manifest and aligned stack documentation with `ld-reset` |
| `README.md`, `docs/remote-development.md`, `infra/README.md` | Documented the Rider-owned application workflow and current command surface |
| `dotfiles/README.md`, `dotfiles/rider/README.md` | Documented placement, cold-start order, frontend modes, SSO prerequisites and Core Tools path |
| `dotfiles/ai/instructions.md`, `infra/bootstrap.sh` | Removed retired command guidance and bootstrap assertions |
| `plans/2026_09_14_rider_run_configurations_result.md` | Reconciled this ledger with the live implementation and verification |

## Manual actions left for the founder

- In **Run > Edit Configurations**, remove the auto-imported launch-profile, Docker and test-project
  entries with **Alt+Delete**. The shared configurations prevent automatic re-import.
- Set **Settings > Tools > Azure Functions > Core Tools executable** to
  `/usr/lib/node_modules/azure-functions-core-tools/bin/func`.
- Re-run `all-backend` from cold three times; if the historical concurrent-start race appears,
  start the hosts individually in manifest order and revise the compounds.
- Run `be-seeder`, `be-test-data-seeder`, `all-stack`, `all-public`, `fe-company-admin` and
  `fe-dev`; confirm the frontend request path and a bound breakpoint.
- Run `az login --use-device-code`, then test `be-backend-sso` with `fe-sso` and confirm the seeded
  data is local.

## Notes

- The implemented names use `be-*` for backend applications and `all-*` for compounds. This is the
  same 21-configuration set described by the plan, with a consistent prefix scheme for Rider's
  combined backend/frontend list.
- Five backing-service containers were running during verification and no application ports were
  listening before the attempted compound launch. The failed launch left no hosts running.
- No seeder or reset was run as part of this reconciliation, so no local data was deliberately
  changed.
