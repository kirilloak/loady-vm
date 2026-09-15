#!/usr/bin/env bash
# Recreate and seed the local backing services from scratch.
#
# This brings up SQL Server, the Cosmos emulator, Redis, Azurite and the APIM proxy, waits until the
# two that need waiting for answer, installs the emulator's fresh certificate, then builds and runs
# Loady.Seeder and Loady.TestDataSeeder. Function hosts and the frontend remain run configurations
# in Rider — see dotfiles/rider/run/ and docs/remote-development.md.
#
# This is the only stack command. Nothing here starts, stops or inspects a long-running application,
# because a second way to do what Rider does would disagree with it sooner or later.
#
# Usage:
#   ld-reset.sh            recreate the containers, wait for them and run both seeders
#   ld-reset.sh --hard     also dotnet clean the solution first
set -euo pipefail
LD_PROG=ld-reset
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/lib.sh"

ld_need az docker jq dotnet python3

REPO="$(ld_repo)"
HARD=0
for arg in "$@"; do
  case "$arg" in
    --hard) HARD=1 ;;
    *)      ld_die "usage: ld-reset.sh [--hard]" ;;
  esac
done

drift_check() {
  # compose/loady-vm.yaml is this repository's own file, so a change the team makes to theirs does
  # not reach it. Compare the two on the things that actually break a local stack — which services
  # exist and which image each one runs — and say so. A warning, not a failure: cosmosdb is here by
  # design and a deliberate difference is the normal case.
  local theirs="$REPO/backend/compose.yaml"
  [[ -f "$theirs" ]] || return 0
  command -v docker >/dev/null || return 0

  local ours_services theirs_services
  ours_services="$(ld_compose config --format json 2>/dev/null \
    | jq -r '.services | to_entries[] | "\(.key)=\(.value.image // "-")"' | sort)" || return 0
  theirs_services="$(docker compose -f "$theirs" --project-directory "$REPO/backend" config --format json 2>/dev/null \
    | jq -r '.services | to_entries[] | "\(.key)=\(.value.image // "-")"' | sort)" || return 0

  local only_theirs
  only_theirs="$(comm -13 <(printf '%s\n' "$ours_services") <(printf '%s\n' "$theirs_services"))"
  if [[ -n "$only_theirs" ]]; then
    ld_warn "compose drift: loady-one/backend/compose.yaml has services this setup does not:
$(printf '%s\n' "$only_theirs" | sed 's/^/         /')
       Reconcile compose/loady-vm.yaml in this repository if the difference is not deliberate."
  fi
}

drift_check

ld_log "checking Azure CLI session"
if ! az account get-access-token --output none >/dev/null 2>&1; then
  ld_warn "Azure CLI session is missing or expired; starting device-code login."
  az login --use-device-code --output none
  az account get-access-token --output none >/dev/null \
    || ld_die "Azure CLI login did not produce an active session"
fi

# Applications are Rider's, so this cannot stop them — and a host left running against a database
# that is about to be destroyed fails in a way that reads as a code problem. Say so; the founder
# stops them with Rider's stop button.
ld_warn "stop any running application in Rider before continuing; the databases are about to go."

"$HERE/slot.sh" claim loadystack "ld-reset in ${REPO/#"$HOME"/\~}"

ld_log "removing containers and volumes"
ld_compose down -v

ld_log "pulling images"
ld_compose pull

if ((HARD)); then
  ld_log "dotnet clean"
  dotnet clean "$REPO/backend/Loady.slnx" --nologo --verbosity quiet
fi

ld_log "containers"
ld_compose up -d

# Probed from the host, not from a container healthcheck: the Cosmos emulator image cannot be
# relied on to carry a tool to check itself with, and the seeders fail confusingly against a
# half-started emulator rather than waiting.
# shellcheck disable=SC2016  # $MSSQL_SA_PASSWORD must expand inside the container, not here
ld_wait_for "sqlserver" 180 docker exec sqlserver sh -c \
  'if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then
     exec /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1"
   else
     exec /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1"
   fi'
ld_wait_for "cosmosdb" 600 curl -fsSk https://localhost:8081/_explorer/emulator.pem

# The emulator generates its certificate into its data volume, so it is new after every reset and
# the trust store has to follow it. Idempotent: a no-op when it is already the trusted one.
"$HERE/cosmos-cert.sh"

SEEDER_DIR="$REPO/backend/src/Seeder/Loady.Seeder"
SEEDER_OUTPUT="$SEEDER_DIR/bin/Debug/net10.0"
TEST_DATA_SEEDER_DIR="$REPO/backend/src/Seeder/Loady.TestDataSeeder"
TEST_DATA_SEEDER_OUTPUT="$TEST_DATA_SEEDER_DIR/bin/Debug/net10.0"

ld_log "building Loady.Seeder"
dotnet build "$SEEDER_DIR/Loady.Seeder.csproj" --nologo --verbosity minimal

ld_log "building Loady.TestDataSeeder"
dotnet build "$TEST_DATA_SEEDER_DIR/Loady.TestDataSeeder.csproj" --nologo --verbosity minimal

ld_log "seeding"
(
  cd "$SEEDER_OUTPUT"
  AZURE_FUNCTIONS_ENVIRONMENT=Localhost EnvironmentName=Localhost \
    dotnet Loady.Seeder.dll -IncludeSeeders -IncludeMigrations -IncludeSqlMigrations -u
)

ld_log "seeding test data"
(
  cd "$TEST_DATA_SEEDER_OUTPUT"
  AZURE_FUNCTIONS_ENVIRONMENT=Localhost EnvironmentName=Localhost \
    dotnet Loady.TestDataSeeder.dll
)

# Configuration rows the seeders do not write, from sql/post-reset/. Every file there is
# re-runnable, so this is safe whether or not the databases were just dropped.
ld_log "post-reset SQL"
"$HERE/ld-sql.sh"

# The seeders know nothing about the founder, and the DEV B2C configurations resolve their user by
# email against this emulator, so a reset leaves `be-backend-sso` returning 401 until this runs.
# A warning rather than a failure: the reset itself has succeeded by here, and the only thing that
# usually goes wrong is an unset git email, which matters to one run configuration out of twenty.
ld_log "local SSO user"
(cd "$REPO" && "$HERE/ld-user.py") || ld_warn "ld-user failed; the *-sso run configurations will 401 until it runs"

ld_log "containers ready and seeded. In Rider: 'stack-all'."
