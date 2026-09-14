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

## First connection

The project path is `/home/dev/loady-one/backend/Loady.slnx`. Confirm the directory Rider creates
for its project files: it should be `backend/.idea/.idea.Loady/.idea/`, and if it is not, correct
`RIDER_DIR` in `dotfiles/sync.sh` to match — the port mapping is synced through that path.
