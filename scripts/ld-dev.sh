#!/usr/bin/env bash
# Start and stop the Loady backend on Linux: the Linux equivalent of loady-one/backend/backend.ps1,
# which is Windows-only where it matters (taskkill, Start-Process into new windows, the Cosmos DB
# Emulator .exe). That file is not modified; this one replaces it.
#
# Each function host runs detached under setsid with its pid and log in the state directory, so
# ld-stop and ld-logs address hosts by name instead of killing every `func` on the machine.
#
# Usage:
#   ld-dev.sh start [--public]     containers, readiness, build, seed, function hosts
#   ld-dev.sh stop                 function hosts, then containers; releases the slot
#   ld-dev.sh restart [--public]
#   ld-dev.sh status
#   ld-dev.sh logs <name> [-f]
#   ld-dev.sh build | seed | containers
set -euo pipefail
LD_PROG=ld-dev
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/lib.sh"

ld_need docker jq dotnet func

REPO="$(ld_repo)"
BACKEND="$REPO/backend"
MANIFEST="$(ld_vm_repo)/compose/processes.json"
RUN_DIR="$LOADY_STATE/run"
DOTNET_TFM="$(jq -r .dotnet "$MANIFEST")"

# backend.ps1 sets both of these; the function hosts read them to pick appsettings.Localhost.json
# and the Localhost authentication middleware.
export AZURE_FUNCTIONS_ENVIRONMENT=Localhost
export EnvironmentName=Localhost

INCLUDE_PUBLIC=0
command="${1:-}"
shift || true
for arg in "$@"; do
  [[ "$arg" == --public ]] && INCLUDE_PUBLIC=1
done

hosts() {
  # hosts: name<TAB>port<TAB>wait for every host this invocation should run, in manifest order.
  jq -r --argjson public "$INCLUDE_PUBLIC" '
    .groups[]
    | select(.public == false or $public == 1)
    | .wait as $wait
    | .processes[]
    | [.name, (.port | tostring), ($wait | tostring)] | @tsv
  ' "$MANIFEST"
}

all_hosts() {
  jq -r '.groups[].processes[] | [.name, (.port | tostring)] | @tsv' "$MANIFEST"
}

host_dir() { printf '%s/src/Domains/%s/bin/Debug/%s\n' "$BACKEND" "$1" "$DOTNET_TFM"; }

running() {
  # running <name>: true when the recorded pid is alive.
  local pid_file="$RUN_DIR/$1.pid" pid
  [[ -f "$pid_file" ]] || return 1
  pid="$(cat "$pid_file")"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

start_containers() {
  "$HERE/slot.sh" claim loadystack "ld-start in ${REPO/#"$HOME"/\~}"
  ld_log "containers"
  ld_compose up -d
  # Probed from the host, not from a container healthcheck: the Cosmos emulator image cannot be
  # relied on to carry a tool to check itself with, and the seeders fail confusingly against a
  # half-started emulator rather than waiting.
  # shellcheck disable=SC2016  # $MSSQL_SA_PASSWORD must expand inside the container, not here
  ld_wait_for "sqlserver" 180 bash -c \
    'docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" 2>/dev/null
     || docker exec sqlserver /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1"'
  ld_wait_for "cosmosdb" 600 curl -fsSk https://localhost:8081/_explorer/emulator.pem
}

build() {
  ld_log "build"
  dotnet restore "$BACKEND/Loady.slnx"
  dotnet build "$BACKEND/Loady.slnx" --no-restore
}

seed() {
  ld_log "seed"
  # Same two seeders and the same flags as backend.ps1, run from their build output.
  ( cd "$BACKEND/src/Seeder/Loady.Seeder/bin/Debug/$DOTNET_TFM" \
    && dotnet Loady.Seeder.dll -IncludeSeeders -IncludeMigrations -IncludeSqlMigrations -u )
  ( cd "$BACKEND/src/Seeder/Loady.TestDataSeeder/bin/Debug/$DOTNET_TFM" \
    && dotnet Loady.TestDataSeeder.dll )
}

start_hosts() {
  mkdir -p "$RUN_DIR"
  local name port wait_seconds last_wait=-1
  while IFS=$'\t' read -r name port wait_seconds; do
    # The manifest groups carry the pauses backend.ps1 uses between waves; a new group's wait is
    # taken once, before its first host.
    if [[ "$wait_seconds" != "$last_wait" ]] && ((wait_seconds > 0)); then
      sleep "$wait_seconds"
    fi
    last_wait="$wait_seconds"

    if running "$name"; then
      echo "    $name already running (pid $(cat "$RUN_DIR/$name.pid"))"
      continue
    fi

    local dir
    dir="$(host_dir "$name")"
    if [[ ! -d "$dir" ]]; then
      ld_warn "$name has no build output at ${dir#"$REPO"/}; run 'ld-build' first"
      continue
    fi

    # ASPNETCORE_URLS binds every interface on purpose: nginx in the apim container reaches these
    # ports across the docker bridge, and a loopback-only host would answer it with nothing.
    ( cd "$dir" && setsid env "ASPNETCORE_URLS=http://0.0.0.0:$port" \
        func start --no-build --port "$port" \
        >"$RUN_DIR/$name.log" 2>&1 </dev/null & echo $! >"$RUN_DIR/$name.pid" )
    echo "    $name on $port (pid $(cat "$RUN_DIR/$name.pid"))"
  done < <(hosts)
}

stop_hosts() {
  ld_log "stopping function hosts"
  local name port pid
  while IFS=$'\t' read -r name port; do
    local pid_file="$RUN_DIR/$name.pid"
    [[ -f "$pid_file" ]] || continue
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      # The process group, because `func` starts the worker as a child and killing only the host
      # leaves the worker holding the port.
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      echo "    stopped $name ($pid)"
    fi
    rm -f "$pid_file"
  done < <(all_hosts)
}

case "$command" in
  start)
    start_containers
    build
    seed
    start_hosts
    ld_log "up. Frontend: ld-fe. APIM: http://localhost:7000/app"
    ;;
  containers)
    start_containers
    ;;
  build) build ;;
  seed) seed ;;
  start-hosts) start_hosts ;;
  stop)
    stop_hosts
    ld_log "containers down"
    ld_compose stop
    "$HERE/slot.sh" release loadystack
    ;;
  restart)
    "$0" stop
    "$0" start "$@"
    ;;
  status)
    printf '%-38s %-6s %s\n' NAME PORT STATE
    while IFS=$'\t' read -r name port; do
      if running "$name"; then
        printf '%-38s %-6s running (pid %s)\n' "$name" "$port" "$(cat "$RUN_DIR/$name.pid")"
      else
        printf '%-38s %-6s stopped\n' "$name" "$port"
      fi
    done < <(all_hosts)
    echo
    ld_compose ps
    echo
    echo "slot loadystack: $("$HERE/slot.sh" holder loadystack || echo free)"
    ;;
  logs)
    name="${1:-}"
    [[ -n "$name" ]] || ld_die "usage: ld-logs <name> [-f]"
    [[ -f "$RUN_DIR/$name.log" ]] || ld_die "no log for '$name' in ${RUN_DIR/#"$HOME"/\~}"
    shift
    tail "${@:--n200}" "$RUN_DIR/$name.log"
    ;;
  *)
    ld_die "usage: ld-dev.sh <start|stop|restart|status|logs|build|seed|containers> [--public]"
    ;;
esac
