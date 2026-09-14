# Rider run configurations for the VM

## Goal

Track Loady's Rider run configurations in this repository and place them into the VM checkout, so
every Loady application — each function host, the frontend in each of its modes, and both seeders —
runs and debugs from Rider over SSH, without anything appearing in `loady-one`'s `git status`.

The division of labour is fixed: Docker runs the backing services only — SQL Server, the Cosmos
emulator, Redis, Azurite and the APIM proxy — and Rider over SSH runs every application. Nothing
about the containers moves into Rider's run list.

One terminal command survives on the stack side: `ld-reset`, which wipes and brings the containers
up. Everything it currently does past that — build, seed, start the hosts — is Rider's job now, and
the `ld-*` commands that did it are retired rather than left as a second way to do the same thing.

Rider is also the only IDE on the VM, so the founder's WebStorm frontend profiles move into the same
Rider project as the backend's.

## Success criteria

- `dotfiles/rider/run/*.run.xml` holds every configuration below.
- `backend/.run` in the checkout is a symlink to that directory, and
  `git -C ~/loady-one status --short` is empty.
- Rider lists the configurations on open, with no import step.
- `ld-reset` is the only stack command left: it wipes, pulls, brings the containers up, waits for
  them and installs the Cosmos certificate, and stops there.
- Once it has run, every application runs from Rider: the seeders, the five default hosts, the six
  public ones, and the frontend in each of its modes.
- Every port in the table in `docs/remote-development.md` is forwarded to the Mac automatically.
- The four WebStorm frontend profiles run in Rider with their behaviour unchanged.
- `backend-api-sso` signs in through the dev B2C tenant while reading and writing the VM's local
  SQL Server, Cosmos emulator, Redis and Azurite.
- Breakpoints in a function bind and hit.
- A worktree created by `ld-stn` has the configurations without a second command.
- No file tracked here contains a B2C client secret, a SendGrid key or any other credential.

## The configurations

Twenty-one files, all of them applications.

| Name | Type | What |
|---|---|---|
| `Loady.Backend.Api` | Azure Functions | port 7160, `Localhost` profile |
| `Loady.Events.Api` | Azure Functions | port 7296 |
| `Loady.Backoffice.Api` | Azure Functions | port 7001 |
| `Loady.Loady2Go.Api` | Azure Functions | port 7152 |
| `Loady.Loady2Share.Api` | Azure Functions | port 7094 |
| `Loady.Public.*` (6) | Azure Functions | ports 7247, 7248, 7249, 7250, 7253, 7254 |
| `backend-api-sso` | Azure Functions | `Loady.Backend.Api` again, `Dev` profile, port 7160, local infrastructure through `envs` |
| `fe-loady-admin` | npm | `frontend`, `yarn start`, local mode, user `9999...` |
| `fe-company-admin` | npm | the same, user `...0001` |
| `fe-sso` | npm | local APIM, `VUE_APP_AUTH_ENABLE_LOCAL_MODE=false`, `PORT=8080` |
| `fe-dev` | npm | the deployed dev APIM, real auth, no local backend |
| `seeder` | .NET project | `Loady.Seeder`, `-IncludeSeeders -IncludeMigrations -IncludeSqlMigrations -u` |
| `test-data-seeder` | .NET project | `Loady.TestDataSeeder`, no arguments |
| `backend` | compound | the five default hosts |
| `public-api` | compound | the six public hosts |
| `stack` | compound | `backend` and `fe-loady-admin` |

The eleven hosts are named exactly as in `compose/processes.json`, which stays the source of truth
for the set and the ports; the configurations repeat the numbers only because Rider cannot read that
file. `Loady.Reports.Api` and `Loady.Imports.Api` stay absent for the reason that manifest gives.

The four frontend configurations are the founder's existing WebStorm profiles, migrated whole. They
are prefixed `fe-` because one Rider project now holds both halves and the WebStorm names do not
survive the merge — `dev` alone is ambiguous beside a backend configuration, and `local-dev-sso` is
the name of the backend one. Renaming back is one `name=` attribute per file.

### One command, then Rider

`ld-reset` absorbs what `ld-dev.sh containers` does — compose up, the readiness waits for SQL Server
and the Cosmos emulator, the certificate install, the `loadystack` claim — and ends there instead of
calling `ld-dev.sh start`. A cold start is then `ld-reset` over ssh, then `seeder`,
`test-data-seeder` and `stack` in Rider. Rider cannot express that order in one button anyway,
because a compound has no ordering.

`scripts/ld-dev.sh` is deleted rather than shrunk. Once the hosts move to Rider, everything left in
it is either container work that belongs in the one script that already wipes and recreates them, or
a process manager Rider replaces: `start_hosts`, `stop_hosts`, `running`, the pid and log directory,
`logs`, `status`, `build` and `seed`. Keeping it as a second way to run the stack is exactly the
duplication this change is for.

Retired with it, from `scripts/loady-shell.zsh`: `ld-start`, `ld-stop`, `ld-restart`, `ld-status`,
`ld-logs`, `ld-build`, `ld-seed` and `ld-fe`. Rider's run panel is the status, its consoles are the
logs, its Build method is the build, and the four `fe-*` configurations are `ld-fe` with more modes
than it had.

Kept: `ld-reset`, `ld-cosmos-cert`, the VM commands (`ld-vm`, `ld-up`, `ld-down`, `ld-tfd`), the
worktree commands (`ld-stn`, `ld-st`, `ld-stl`, `ld-str`), the migration commands (`ld-add`,
`ld-update`, `ld-remove`, `ld-mig`), and `slot.sh`, which `ld-reset` still claims so a second
worktree gets a clear refusal rather than a port collision.

What is lost, stated rather than discovered: nothing brings the containers back up without wiping
them. Docker's `restart: unless-stopped` covers a reboot, which is the only way they stop now that
`ld-stop` is gone, so the gap is narrow — and `ld-reset` is the answer if it is ever hit.

## The staggered start

`scripts/ld-dev.sh` starts the hosts in groups with a 20-second pause between them, and
`compose/processes.json` says why: *"the first two hosts warm the shared runtime and the rest fail to
bind if they all start at once."* It inherits this from `backend/backend.ps1`.

**A Rider compound starts every member at once and offers no delay and no ordering.** So `backend`
and `stack` run head-first into the one thing the existing launcher goes out of its way to avoid.
This is the plan's main risk and it is checked early, in step 3, not discovered in step 7.

Three outcomes, and the work that follows each:

1. **It works.** Plausible: the pauses come from a PowerShell script that opened a new console
   window per host on Windows, and the failure it avoids may be a Core Tools extraction race that a
   warm `~/.azure-functions-core-tools` no longer has. Then the compounds stand as written.
2. **It fails intermittently.** Then `stack` keeps only what a session actually needs — commonly
   `Loady.Backend.Api`, `Loady.Events.Api` and the frontend — and the rest are started from Rider
   individually when a task needs them. The compound is a convenience, not the deliverable.
3. **It fails every time.** Then the compounds are dropped and the hosts are started individually
   in manifest order, which is a few extra clicks at the start of a session and nothing else.
   Running eleven hosts under the debugger at once was never the point, and step 5 should then keep
   `compose/processes.json`'s `wait` field as the record of why the order matters.

Deciding this before step 3 would be guessing. The step is cheap and the answer is binary.

## Binding and forwarding

The founder's requirement is that everything be reachable from the Mac. The way to get that is
**not** to bind the hosts to `127.0.0.1`, and this is worth stating precisely because the intuition
points the wrong way.

A forwarded port — Rider's forwarding or `ssh -L` — is a tunnel whose far end connects to
`localhost:<port>` *on the VM*. A socket bound to `0.0.0.0` accepts that connection exactly as a
loopback-bound one does. So `0.0.0.0` is forwardable, and binding `127.0.0.1` buys nothing on the
Mac side while breaking the container side: nginx in the `apim` container reaches the hosts across
the Docker bridge, from an address that is not loopback, and a loopback-only host answers it with
nothing. `docs/remote-development.md` records this as the reason every host is started with
`ASPNETCORE_URLS=http://0.0.0.0:<port>`, and it is why `scripts/ld-dev.sh` exports it.

It is also not an exposure. The Docker daemon is configured to publish to `127.0.0.1`, the compose
file binds `127.0.0.1` explicitly, ufw denies inbound except SSH and the bridge back to the host
ports, and there is no router port-forward to the VM. `0.0.0.0` on this machine means the Docker
bridge and loopback, and nothing else.

So the run configurations keep `0.0.0.0`, and the reachability requirement is met the other way: by
forwarding every port rather than only six. `dotfiles/rider/forwardedPorts.xml` currently tracks
`8080`, `7000`, `7160`, `7296`, `1433` and `6379`; it grows to the whole table in
`docs/remote-development.md` — the eleven host ports, `8080`, `7000`, `1433`, `6379`, `8081`, `1234`
and `10000`-`10002`, twenty entries. `sync.sh` already carries that file both ways and
`--seed-worktree` already puts it into every new worktree, so nothing new is needed to distribute
it.

The Docker ports need no change: the compose file publishes them on `127.0.0.1`, which is precisely
what a tunnel connects to. They are forwardable today and the only thing missing was the entries.

## Where they come from

All four XML shapes are the founder's own and are copied rather than invented:

| Source | Gives |
|---|---|
| `~/Repositories/kirill/settings/work/run/rider/local-dev-sso.run.xml` | the Azure Functions type: `type="AzureFunctionAppRun" factoryName="Azure - Run Function"`, `PROJECT_FILE_PATH`, `LAUNCH_PROFILE_NAME`, `PROGRAM_PARAMETERS` carrying `host start --port <port>`, `WORKING_DIRECTORY` at the build output, and the SSO `envs` |
| `~/Repositories/kirill/settings/work/run/webstorm/*.run.xml` | all four frontend configurations, whole: `js.build_tools.npm`, `command value="start"`, `package-manager value="yarn"`, `node-interpreter value="project"`, the `VUE_APP_*` envs of each, `PORT=8080` on the SSO one, and the browser-with-JS-debugger extension |
| `~/costfluent/.run/*.run.xml` | `DotNetProject` for the seeders and `CompoundRunConfigurationType` for the compounds |

Running each function host as a plain .NET project instead is rejected: these are isolated-worker
functions, so `dotnet run` starts the worker without the Functions host and no trigger fires.

## Where they live

`backend/.run/`, as a symlink to `dotfiles/rider/run/` in this repository. This is the founder's own
prior arrangement — `~/Repositories/loady/loady-one/backend/.run` is exactly such a symlink — and it
is the pattern `scripts/link-agent-files.sh` already implements for `backend/CLAUDE.md` and
`backend/AGENTS.md`: symlink in, and add a `.git/info/exclude` entry if the checkout does not already
ignore the path. That file is local to the checkout and never pushed, so rule 1 holds; the old
checkout hides `/backend/.run` and `/frontend/.run` that way today.

`.idea/.idea.Loady/.idea/runConfigurations/` with a `dotfiles/sync.sh` manifest entry was an earlier
choice here and is rejected. It works, but `.run` is Rider's documented location and the one these
configurations were written for, and a two-way content sync with state files and conflict handling is
a great deal of machinery for what a symlink does exactly. Under a symlink an edit made in Rider's UI
lands directly in this repository's working tree, which is what `sync.sh` exists to simulate for files
that cannot be symlinked.

Consequences worth stating:

- `$PROJECT_DIR$` is `backend/`, the directory holding `.idea`, so a host is
  `$PROJECT_DIR$/src/Domains/<name>/<name>.csproj` and the frontend is
  `$PROJECT_DIR$/../frontend/package.json`. Every configuration stays inside the checkout, which is
  a second reason the containers are not in this list: reaching `~/loady-vm` would mean an absolute
  path in a tracked file.
- The WebStorm configurations were rooted at `frontend/` itself and every one has to be re-rooted.
  That is the whole of the frontend migration; the four files are otherwise copied unchanged.
- Reaching `../frontend` needs Solution Explorer's **Show All Files**, which
  `dotfiles/rider/README.md` already requires for an unrelated reason. A run configuration resolves
  the path regardless of what the tree displays, so this affects editing the frontend, not running it.
- Every worktree's `backend/.run` points at the same directory, so the configurations are shared and
  an edit in one worktree changes all of them. That is wanted. `$PROJECT_DIR$` still resolves per
  worktree, which is what makes one shared directory correct rather than merely convenient.
- `ld-stream.sh` already calls `link-agent-files.sh` for every new worktree, so no new seeding step
  is needed. `sync.sh --seed-worktree` keeps its current job, the port mapping, and is untouched.

## The SSO configuration

`backend-api-sso` is the founder's `local-dev-sso.run.xml` with the modifications the VM needs. What
it is: `Loady.Backend.Api` on the `Dev` launch profile, so `AZURE_FUNCTIONS_ENVIRONMENT=Development`
and the real B2C sign-in flow from `appsettings.Development.json` applies, with `envs` that point the
infrastructure back at this machine — Cosmos emulator, local SQL Server, local Redis, Azurite queues,
and `FrontendSettings__FrontendUrl` at `http://localhost:8080` so the B2C redirect lands on the local
frontend. `TRACK_ENVS` is `0`, which is what makes those envs win over the launch profile's.

Its pair `fe-sso` is the WebStorm `local-dev-sso` unchanged: `PORT=8080`,
`VUE_APP_API_BASE_URL=http://localhost:7000/app`, `VUE_APP_AUTH_ENABLE_LOCAL_MODE=false`. `fe-dev` is
the other real-auth one and is not its pair: it points at the deployed dev APIM, so it needs no
backend, no containers and no `az login`, and it is the one configuration here that touches nothing
on this machine but the dev server.

Four things follow that the original did not have to care about on a Mac:

- **It needs `ASPNETCORE_URLS=http://0.0.0.0:7160`, which the original does not set.** On Docker
  Desktop a loopback-bound host is reachable from a container; on Docker Engine it is not, and the
  `apim` container answers every `/app` call with a 502. `scripts/ld-dev.sh` exports this for the
  hosts it starts and `docs/remote-development.md` explains it. This is the single most likely thing
  to be missed, because the configuration starts cleanly without it. It applies to all eleven hosts,
  not only this one.
- **The overrides are partial by design.** Cosmos, SQL, Redis, queues and the frontend URL are
  redirected locally; Key Vault, Azure Search and the photo, assets and translations blob accounts
  still point at the real `-dev` resources and use `DefaultAzureCredential`. So the VM needs an Azure
  identity — `az login --use-device-code`, since it is headless. `azure-cli` is installed by
  `infra/bootstrap.sh:255`. Without it the host starts and then fails on the first Key Vault or
  Search call, not at startup.
- **The B2C redirect still works from the VM.** The browser is on the Mac and reaches the dev server
  through the forwarded port, so it sees `http://localhost:8080` exactly as it did on the Mac and the
  existing reply URL covers it. Nothing needs registering in the tenant.
- **Nothing secret is copied.** `appsettings.Development.json` in `loady-one` carries a B2C client
  secret and a SendGrid key; they stay there and are read from there. The tracked XML here holds only
  the local defaults `compose/loady-vm.yaml` already states in the open — the SA password
  `Passw0rd!` and the Cosmos emulator's published key. This is a hard line on the file.

`ld-fe` has no real-auth switch and no company or user override beyond its two positional arguments,
so `fe-sso` and `fe-dev` are Rider-only. Teaching `ld-fe` the same modes is a separate small change,
out of scope here.

## Blockers

The VM is not reachable (`ssh loady-vm` times out), so steps 3 onward wait on it. Steps 1, 2 and 6
do not.

## Steps

1. **Write the twenty-one configurations into `dotfiles/rider/run/`.** The eleven hosts,
   `backend-api-sso`, the four frontend ones, the two seeders, and the three compounds.
   Why: this repository is where they are tracked, and their XML shapes are in hand.
   Depends on: nothing.
   Notes: `ASPNETCORE_URLS=http://0.0.0.0:<port>` on every host including the SSO one, for the
   reason the *Binding and forwarding* section gives — not `127.0.0.1`, which would break APIM
   without helping the Mac;
   `AZURE_FUNCTIONS_ENVIRONMENT=Localhost` and `EnvironmentName=Localhost` on the ten local-mode
   hosts and both seeders, matching `scripts/ld-dev.sh`; the seeders get the working directory and
   arguments `ld-dev.sh seed` uses; the four frontend files change only `name` and `package-json`.
   Verification: `xmllint --noout dotfiles/rider/run/*.run.xml`; each host's name and port read back
   against `compose/processes.json`; each `PROJECT_FILE_PATH` resolved against the checkout so a
   typo is caught here and not in Rider.

2. **Teach `scripts/link-agent-files.sh` about `backend/.run`.** One directory symlink to
   `$VM_REPO/dotfiles/rider/run`, and `backend/.run` added to the exclude list its loop walks.
   Why: it is the script that already owns "put a file from here into that checkout without the
   checkout showing it", and extending it means `ld-stn` and every existing call site get the
   configurations for free.
   Depends on: step 1.
   Notes: `link_one` creates file symlinks and needs a directory case, using `ln -sfn` so a relink
   does not nest a link inside the existing target. Add the exclude entry before creating the
   symlink: `git check-ignore` refuses a path beyond a symbolic link, which is how the old checkout
   answers for `backend/.run/local-dev-sso.run.xml` today. Extend the script's closing assertion to
   cover `backend/.run` — that assertion is the guarantee, and a new linked path outside it is
   unguarded.
   Verification: `shellcheck scripts/link-agent-files.sh`; then run it against a throwaway clone and
   confirm `git status --porcelain` is empty, the exclude file has one `/backend/.run` line, and a
   second run adds no duplicate.

3. **Test the simultaneous start.** With containers up and the solution built, run the `backend`
   compound from cold, three times.
   Why: the 20-second stagger in `ld-dev.sh` exists because these hosts are documented to fail when
   started at once, and a Rider compound cannot stagger. Everything about `backend` and `stack`
   depends on the answer, and finding out in step 7 would mean rewriting the compounds then.
   Depends on: steps 1 and 2, and the containers being up.
   Verification: all five hosts bind and answer on their ports, three runs out of three. If any run
   fails, read the failing host's console for the actual error before concluding — a port already
   held by a host from an earlier `ld-start` is a different problem with the same symptom. Then take the branch the
   *The staggered start* section sets out, and amend this plan before continuing.

4. **Confirm the plugins, the interpreter and the link.** With Rider connected: the Azure Toolkit
   plugin is installed, Rider's bundled JavaScript and Node support is present and
   `node-interpreter value="project"` resolves to a real interpreter, and Rider lists all
   twenty-one from the symlinked `.run`.
   Why: assumptions the files rest on, none checkable from the Mac. The Node one is new to this
   arrangement: the WebStorm profiles ran in WebStorm, where that support is a given, and Rider is a
   different product.
   Depends on: step 2.
   Verification: all twenty-one appear and are runnable, not greyed out. If the Azure Toolkit is
   missing the founder installs it. If the interpreter does not resolve, pin the VM's node path in
   the four npm files and record it in `dotfiles/rider/README.md`.

5. **Retire the app commands.** Delete `scripts/ld-dev.sh`; move its container work into
   `scripts/ld-reset.sh`, which drops `--public` and ends at containers-ready; remove `ld-start`,
   `ld-stop`, `ld-restart`, `ld-status`, `ld-logs`, `ld-build`, `ld-seed` and `ld-fe` from
   `scripts/loady-shell.zsh`.
   Why: two ways to run the same stack is the complexity this change exists to remove, and the
   second way silently disagrees with the first — `ld-status` reads a pid directory Rider never
   writes to, so it would report every Rider-started host as stopped.
   Depends on: step 4, so the configurations are known to work before their replacement is deleted.
   Notes: every file that names one of these commands has to follow, and there are more than the
   scripts themselves — `scripts/ld-stream.sh` (the slot line in `new` and the `ld-stop` hint in
   `remove`), `scripts/slot.sh`, `scripts/lib.sh` and `scripts/cosmos-cert.sh` in comments, the
   `ld-*` row in `AGENTS.md`'s knowledge table, and `docs/remote-development.md` throughout.
   `compose/processes.json` keeps its names and ports — bootstrap's ufw rules and the Rider
   configurations both depend on them — but its `wait` field describes a stagger nothing performs
   any more; keep or drop it according to what step 3 found.
   Verification: `shellcheck scripts/*.sh`, `zsh -n scripts/loady-shell.zsh`, a fresh login shell
   offering the kept commands and none of the retired ones, and `ld-reset` from cold leaving five
   healthy containers and no function host.

6. **Forward every port.** Extend `dotfiles/rider/forwardedPorts.xml` from six entries to the twenty
   the port table lists.
   Why: the reachability requirement, met the way that does not break APIM.
   Depends on: nothing; independent of the rest and doable while the VM is down.
   Verification: `xmllint --noout dotfiles/rider/forwardedPorts.xml`; after a Rider reconnect the
   Ports tool window lists all twenty; `sync.sh --check` reports no conflict on the file.

7. **Run every application from Rider, cold.** `ld-reset` over ssh first, then
   `seeder`, `test-data-seeder`, `stack` and `public-api` in Rider. Set a breakpoint in a `Loady.Backend.Api` function and hit it through the
   frontend. Also `fe-company-admin` and `fe-dev`, the latter needing none of the above and so
   proving the npm configurations in isolation.
   Why: this is the criterion the whole plan is for, and the `ASPNETCORE_URLS` and
   `$PROJECT_DIR$/../` changes in step 1 are exactly the kind that look right and are not.
   Depends on: steps 5 and 6, and step 3's answer having been applied to the compounds.
   Notes: the npm configurations run `yarn start` only, where `ld-fe` also runs
   `yarn install --frozen-lockfile`. After a lockfile change the first Rider run fails until
   `yarn install` has been run once; decide then whether that belongs as a before-launch step or a
   line in the README. The browser extension the WebStorm files carry opens a browser with the JS
   debugger attached; on a headless VM there is none, so confirm whether Rider forwards the open to
   the Mac's browser or fails. If it fails, drop the extension block from the four files — it is a
   convenience, and the Mac's browser reaches the dev server through the forwarded port either way.
   Verification: the frontend loads at `http://localhost:8080` and its calls reach APIM at 7000; the
   breakpoint binds and hits; `git -C ~/loady-one status --short` is empty.

8. **Run the SSO pair.** `az login --use-device-code` on the VM first, then
   `backend-api-sso + fe-sso`, with `Loady.Backend.Api` stopped so 7160 is free, and sign in through
   the dev B2C tenant.
   Why: this is the configuration with the most that can go wrong, and its whole point is real auth
   over local data.
   Depends on: step 7.
   Verification: sign-in completes and the frontend loads data; a row the test data seeder wrote is
   visible, proving the data is local and not the dev environment's; `ld-logs Loady.Backend.Api`
   shows no Key Vault or Search credential failure.

9. **Document.** A `## Run configurations` section in `dotfiles/README.md` naming the directory, the
   symlink and `link-agent-files.sh` as its placer — and correcting that file's "What is synced"
   table, which otherwise implies everything under `dotfiles/` goes through `sync.sh`. In
   `dotfiles/rider/README.md`: the cold-start order beginning with `ld-reset`, the two
   frontend modes, `az login` as a manual
   prerequisite for the SSO pair, and whatever step 3 decided about the compounds. In
   `docs/remote-development.md`: the division of labour — Docker for the backing services, Rider for
   every application, `ld-reset` the one command between them — the corrected forwarding column now
   that every port is tracked, and the removal of every reference to a retired command. One line in `scripts/link-agent-files.sh`'s
   header, which says it places the agent files and will then place more.
   Why: `AGENTS.md` gives one owner per fact, and this change makes several existing documents
   wrong at once — the command surface, the ports and the way the stack is run.
   Depends on: step 8.
   Verification: read back; no duplicated port table, a link instead.

## Assumptions

- The VM's Rider has the Azure Toolkit plugin, or the founder installs it. Step 4 tests this.
- Rider follows a symlinked `.run` directory. The founder's old checkout has done so since August.
- Rider runs a `js.build_tools.npm` configuration as WebStorm did. The type is shared across the IDEs
  and Rider bundles the JavaScript support, so this is expected rather than hoped for, but it is the
  one part of the frontend migration with no prior art on this machine. Step 4 checks it.
- Eleven function hosts, a dev server and Rider's indexer fit the VM. `infra/bootstrap.sh:694` raised
  the file-descriptor limit for exactly this shape, so it was anticipated; memory under all eleven at
  once has not been measured, and step 7 is the first time it will be.
- `Loady.Backend.Api`'s `Dev` launch profile still means the dev B2C tenant. It is `loady-one`'s file
  and the team may change it; the configuration names the profile rather than restating it, so it
  follows such a change rather than drifting from it.
- Debugging a function host under the Functions runtime works in remote-development mode. Step 7
  tests it; if attach fails the configurations still run and the limitation gets documented.

## Risks

- **The simultaneous start.** Its own section above, and step 3.
- `func` is on the VM's PATH for the login shell, but Rider's backend may not inherit it. The symptom
  in step 4 is a configuration that cannot find Core Tools; the fix is the toolkit's own Core Tools
  path setting, which then belongs in `dotfiles/rider/README.md` as a manual setting.
- `backend-api-sso` collides with `Loady.Backend.Api` — both are 7160 and only one may run. A bind
  failure, not corruption,
  but nothing arbitrates it once the hosts are Rider's. Step 5 removes the command that would
  otherwise collide.
- The SSO configuration writes to real dev Azure resources for anything not overridden: Key Vault is
  read-only, but Azure Search and the blob accounts are shared with the team's dev environment. Worth
  knowing before running a seeder while it is up.
- Both seeders write to the live local databases. That is what they are for, and `ld-reset` is the
  way back, but running `seeder` from Rider by accident is the same mistake as running it from a
  terminal.
- The shared `.run` directory means a configuration edited while working in one worktree changes
  every worktree. Acceptable, and the reason a configuration should not be edited to hold
  branch-specific values.

## Open questions

None. Scope, the host set, the frontend set, the SSO pair and the placement are decided above. The
one live unknown, whether a compound can start five hosts at once, is a measurement rather than a
decision, and step 3 takes it.
