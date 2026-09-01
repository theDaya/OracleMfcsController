#!/usr/bin/env bash
# Run SQL against the mdutilstst01 integration schema.
#
#   deploy/mdutils/sql.sh script.sql                      # run a file
#   echo "select 1 from dual;" | deploy/mdutils/sql.sh    # run stdin
#
# Two things this handles so callers do not have to:
#   - appends "exit", because SQLcl otherwise sits in its REPL waiting on stdin
#     and the caller hangs until it is killed
#   - strips the JVM warnings SQLcl prints before every single result
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$here/connect.env" ]; then
    echo "deploy/mdutils/connect.env is missing - see deploy/mdutils/README.md" >&2
    exit 1
fi
# shellcheck disable=SC1091
source "$here/connect.env"

run="$(mktemp)"
trap 'rm -f "$run"' EXIT
if [ $# -ge 1 ]; then
    cat "$1" > "$run"
else
    cat > "$run"
fi
printf '\nexit\n' >> "$run"

"$SQLCL" -thin -S -L "$DB_CONN" "@$run" 2>&1 \
    | grep -vE "^WARNING: (A restricted method|java\.lang|Use --enable|Restricted methods|Final field|Mutating final)" \
    | grep -v "^$" || true
