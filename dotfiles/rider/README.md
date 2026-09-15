# Rider manual settings

Settings `sync.sh` cannot carry: they live in Rider's own configuration store rather than in a
project file under this repository, so they are applied by hand after connecting a new backend or
resetting settings. Keep this list current — a setting that is not here will be missed on the next
machine.

## Rider in SSH (remote development) mode

- **Tools > SSH Agent Forwarding > Enable SSH agent forwarding — off.** The VM has its own key to
  Azure DevOps, placed by `infra/bootstrap.sh` and bound to the checkout with
  `core.sshCommand`. Forwarding the Mac's agent would make pushes work for the wrong reason: they
  would then depend on an interactive Mac session, and break in tmux, cron and every headless
  backend.
- **Solution Explorer > Show All Files — on.** The solution is `backend/Loady.slnx`, so the rest of
  the repository (`frontend/`, `e2etests/`, `infra/`) is otherwise invisible. Machine-local.
- **Settings > Build > Toolset — the SDK from `backend/global.json`.** Rider normally finds it;
  check it after a .NET SDK upgrade.
- **Tools > Change Memory Settings (on Host) > 4000 > Save and Restart.**

## First connection

The project path is `/home/dev/loady-one/backend/Loady.slnx`. Confirm the directory Rider creates
for its project files: it should be `backend/.idea/.idea.Loady/.idea/`, and if it is not, correct
`RIDER_DIR` in `dotfiles/sync.sh` to match — the port mapping is synced through that path.

`backend/.run` is synced against this repository by `scripts/sync-agent-files.sh`. Rider should list 21
shared configurations with the `be-`, `fe-` and `stack-` prefixes. The Azure Toolkit plugin and
Rider's JavaScript and Node.js support must be enabled; the four `fe-*` configurations use the
project Node interpreter and Yarn.

Set **Settings > Tools > Azure Functions > Core Tools executable** to
`/usr/lib/node_modules/azure-functions-core-tools/bin/func`. Rider's automatic lookup does not
follow this VM's npm-installed `/usr/bin/func` launcher correctly, although that launcher works in
the login shell.

On an existing Rider workspace, open **Run > Edit Configurations**, select the auto-imported
`Project: Profile`, Docker and test-project entries, and remove them with **Alt+Delete**. Rider only
auto-imports launch profiles when a solution has no configurations; the shared configurations now
prevent them from returning unless **Generate Configurations** is invoked on `launchSettings.json`.

## Run configurations

Docker owns only SQL Server, Cosmos DB, Redis, Azurite and the APIM proxy. Start from cold with
`ld-reset`, which builds and runs both seeders, then run `stack-all`. Keep `be-seeder` and
`be-test-data-seeder` for rerunning them independently.
`stack-be-fe` starts only the main backend and frontend, while `stack-public-apis` starts the six
public function hosts when needed. The compound configurations start their members
concurrently; if a cold start exposes the historical Functions runtime race, start the `be-*`
members individually in the order recorded by `compose/processes.json`.

The frontend choices are:

- `fe-loady-admin` and `fe-company-admin`: local APIM with fixed local identities.
- `fe-sso`: local APIM with real dev B2C authentication; pair it with `be-backend-sso`.
- `fe-dev`: deployed dev APIM with real authentication; no local backend or containers required.

`be-backend-sso` and `be-backend` both use port 7160, so stop one before starting the other. Before
using the SSO pair, run `az login --use-device-code` on the VM; the backend still reads the dev Key
Vault, Azure Search and blob accounts through `DefaultAzureCredential`.
