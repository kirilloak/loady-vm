#!/usr/bin/env bash
# Run SQL against the local SQL Server, through the container's own sqlcmd.
#
# Its reason to exist is sql/post-reset/: configuration rows the seeders do not write, which the
# founder needs back every time ld-reset drops the databases. ld-reset applies that directory as its
# last SQL step, and this command applies it again by hand, or one file, or one statement.
#
# Every file in sql/post-reset/ must be safe to apply twice: ld-reset destroys the data before
# calling this, but running it by hand against a live database is the normal case and a plain
# INSERT would duplicate the row. Guard with IF NOT EXISTS, or write an UPDATE beside it.
#
# Usage:
#   ld-sql                     apply sql/post-reset/*.sql in name order
#   ld-sql <file>...           apply those files instead
#   ld-sql -q "SELECT 1"       run one statement
set -euo pipefail
LD_PROG=ld-sql
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/lib.sh"

ld_need docker

CONTAINER="${LOADY_SQL_CONTAINER:-sqlserver}"
DATABASE="${LOADY_SQL_DATABASE:-loady}"

ld_sqlcmd() {
  # The tools path moved between image generations, as in the compose healthcheck: try the current
  # one, then the old one. -b makes sqlcmd exit non-zero on a SQL error, which it does not by
  # default, so a failing file fails the command instead of scrolling past.
  # Plain POSIX sh: the container's /bin/sh is not guaranteed to be bash, so no ${@:2} here.
  docker exec -i "$CONTAINER" sh -c \
    'db=$1; shift
     if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then tool=/opt/mssql-tools18/bin/sqlcmd
     else tool=/opt/mssql-tools/bin/sqlcmd; fi
     exec "$tool" -C -b -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d "$db" "$@"' \
    sh "$DATABASE" "$@"
}

docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true \
  || ld_die "the $CONTAINER container is not running; ld-reset starts it"

if [[ "${1:-}" == "-q" ]]; then
  [[ -n "${2:-}" ]] || ld_die 'usage: ld-sql -q "<statement>"'
  ld_sqlcmd -Q "$2"
  exit
fi

files=()
if (($#)); then
  files=("$@")
else
  # A directory with no .sql file in it is an empty setup, not an error.
  while IFS= read -r file; do files+=("$file"); done < <(
    find "$(ld_vm_repo)/sql/post-reset" -maxdepth 1 -name '*.sql' | sort
  )
fi

if ((${#files[@]} == 0)); then
  ld_log "no SQL to apply"
  exit
fi

for file in "${files[@]}"; do
  [[ -r "$file" ]] || ld_die "cannot read $file"
  ld_log "applying ${file##*/}"
  ld_sqlcmd -i /dev/stdin < "$file"
done
