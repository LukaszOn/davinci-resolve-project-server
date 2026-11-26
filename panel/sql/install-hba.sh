#!/bin/sh
set -eu
umask 077

admin=${1:-postgres}
control=${2:-postgres}
psql_call() { psql -X -v ON_ERROR_STOP=1 -U "$admin" -d "$control" "$@"; }
hba=$(psql_call -Aqt -c 'SHOW hba_file;')
test -f "$hba"
begin='# BEGIN DAVINCI RESOLVE PANEL'
end='# END DAVINCI RESOLVE PANEL'
staged=$(mktemp "${hba}.panel-new.XXXXXX")
backup=$(mktemp "${hba}.panel-original.XXXXXX")
cp -p "$hba" "$backup"
replaced=0
finished=0
cleanup() {
    if [ "$replaced" = 1 ] && [ "$finished" != 1 ]; then
        mv -f "$backup" "$hba"
        printf '%s\n' 'SELECT pg_reload_conf();' | psql_call >/dev/null || true
    fi
    rm -f "$staged" "$backup"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

{
    printf '%s\n' "$begin"
    printf 'local "%s" resolve_panel_agent scram-sha-256\nhost "%s" resolve_panel_agent all scram-sha-256\n' "$control" "$control"
    psql_call -Aqt <<'SQL'
SELECT format('local "%s" +%s scram-sha-256', name, access_role) || chr(10) ||
       format('host "%s" +%s all scram-sha-256', name, access_role)
FROM resolve_access.libraries ORDER BY name;
SQL
    printf '%s\n' 'local all resolve_panel_agent,+resolve_panel_members reject' 'host all resolve_panel_agent,+resolve_panel_members all reject' "$end"
    awk -v begin="$begin" -v end="$end" '
        $0 == begin { if (inside) exit 2; inside=1; next }
        $0 == end { if (!inside) exit 2; inside=0; next }
        !inside { print }
        END { if (inside) exit 2 }
    ' "$hba"
} > "$staged"

if ! cmp -s "$hba" "$staged"; then
    mv -f "$staged" "$hba"
    replaced=1
fi
errors=$(psql_call -Aqt -c 'SELECT line_number || chr(58) || error FROM pg_hba_file_rules WHERE error IS NOT NULL;')
if [ -n "$errors" ]; then
    printf '%s\n' "$errors" >&2
    exit 1
fi
test "$(psql_call -Aqt -c 'SELECT pg_reload_conf();')" = t
finished=1
