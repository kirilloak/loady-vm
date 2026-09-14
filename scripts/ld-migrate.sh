#!/usr/bin/env bash
# EF Core migrations against the local SQL Server: what the old ld-add / ld-update / ld-remove
# aliases did, fixed and moved here.
#
# The connection string is passed as `-- --connection <value>` rather than left to the environment.
# AppDbContextDesignFactory reads the argument first and the loady_relational_database_connection
# variable second, and only the argument is guaranteed to be there in an agent's non-interactive
# shell, where the profile has not been sourced.
#
# Usage:
#   ld-migrate.sh add <name>
#   ld-migrate.sh update [target]
#   ld-migrate.sh remove
#   ld-migrate.sh list
set -euo pipefail
LD_PROG=ld-migrate
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/lib.sh"

ld_need dotnet

REPO="$(ld_repo)"
PROJECT="$REPO/backend/src/Shared/Loady.Relational.Infrastructure"
[[ -d "$PROJECT" ]] || ld_die "no $PROJECT"

command="${1:-}"
shift || true

ef() {
  # dotnet-ef is a global tool on the VM; bootstrap.sh installs it.
  ( cd "$PROJECT" && dotnet ef "$@" -- --connection "$LOADY_SQL_CONNECTION" )
}

case "$command" in
  add)
    name="${1:-}"
    [[ -n "$name" ]] || ld_die "usage: ld-add <MigrationName>"
    ef migrations add "$name"
    echo
    echo "Added. Review the generated files, then 'ld-update' to apply them."
    echo "Nothing is committed: AGENTS.md rule 2."
    ;;
  update)
    if [[ -n "${1:-}" ]]; then ef database update "$1"; else ef database update; fi
    ;;
  remove)
    ef migrations remove
    ;;
  list)
    ef migrations list
    ;;
  *)
    ld_die "usage: ld-migrate.sh <add|update|remove|list>"
    ;;
esac
