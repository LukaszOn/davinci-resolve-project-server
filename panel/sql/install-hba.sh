#!/bin/sh
set -eu
umask 077

admin=${1:-postgres}
control=${2:-postgres}
layout=${3:?Set the access module layout}
agent=${4:?Set the panel service account}
next_agent=${5:-}
case "$layout" in
    [!a-z]*|*[!a-z0-9_]*) printf '%s\n' 'Invalid access module layout.' >&2; exit 2 ;;
esac
for login in "$agent" "$next_agent"; do
    case "$login" in
        [!a-z]*|*[!a-z0-9_]*) printf '%s\n' 'Invalid panel service account name.' >&2; exit 2 ;;
    esac
done
logins="\"$agent\""
if [ -n "$next_agent" ]; then logins="$logins,\"$next_agent\""; fi
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
    printf 'local "%s" %s scram-sha-256\nhost "%s" %s all scram-sha-256\n' "$control" "$logins" "$control" "$logins"
    psql_call -Aqt -v "registry=${layout}_access" <<'SQL'
SELECT format('local "%s" +%s scram-sha-256', name, access_role) || chr(10) ||
       format('host "%s" +%s all scram-sha-256', name, access_role)
FROM :"registry".libraries ORDER BY name;
SQL
    printf 'local all %s,+%s_panel_members reject\nhost all %s,+%s_panel_members all reject\n%s\n' "$logins" "$layout" "$logins" "$layout" "$end"
    awk -v begin="$begin" -v end="$end" -v layout="$layout" -v db="\"$control\"" '
        BEGIN {
            previous_begin = "# BEGIN " toupper(layout) " RESOLVE PANEL"
            previous_end = "# END " toupper(layout) " RESOLVE PANEL"
        }
        $0 == begin || $0 == previous_begin {
            if (inside) exit 2
            inside = ($0 == begin ? end : previous_end)
            first_rule = 1
            next
        }
        $0 == end || $0 == previous_end { if ($0 != inside) exit 2; inside=""; next }
        inside && first_rule && $1 == "local" {
            if ($2 != db) {
                print "The managed pg_hba.conf block belongs to another registry database. Use --remote with separately maintained rules." > "/dev/stderr"
                exit 2
            }
            first_rule = 0
        }
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
