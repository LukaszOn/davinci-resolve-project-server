#!/bin/sh
set -eu
umask 077
cd "$(dirname "$0")"

mode=container
if [ "${1:-}" = --remote ]; then mode=remote; shift; fi
if [ "${1:-}" = --managed-volume ]; then mode=managed; shift; fi
if [ "$#" -eq 0 ]; then
    printf '%s\n' 'Użycie: sh install-db.sh [--remote] BIBLIOTEKA [BIBLIOTEKA ...]' >&2
    exit 2
fi
for library in "$@"; do
    case "$library" in
        ''|*[!a-zA-Z0-9_]*|postgres|template0|template1) printf 'Nieprawidłowa nazwa biblioteki: %s\n' "$library" >&2; exit 2 ;;
    esac
    if [ "${#library}" -gt 63 ]; then printf 'Nazwa biblioteki jest za długa.\n' >&2; exit 2; fi
done

container=${PANEL_POSTGRES_CONTAINER:-postgres}
admin=${PANEL_POSTGRES_ADMIN:-postgres}
config=${PANEL_ENV_FILE:-panel.env}
if [ "$mode" != container ]; then
    admin=${PGUSER:-postgres}
    export PGCLIENTENCODING=UTF8
    : "${PGHOST:?Ustaw PGHOST dla połączenia administracyjnego}"
fi
if [ "$mode" = remote ]; then
    config=${PANEL_ENV_FILE:-.env}
    test -f "$config"
fi
control_from_file=''
if [ "$mode" != managed ] && [ -f "$config" ]; then
    control_from_file=$(sed -n 's/^PANEL_DB_NAME=//p' "$config")
fi
control=${PANEL_CONTROL_DATABASE:-${control_from_file:-postgres}}
case "$control" in ''|*[!a-zA-Z0-9_]*|template0|template1) printf 'Nieprawidłowa nazwa bazy rejestru.\n' >&2; exit 2 ;; esac
in_postgres() {
    docker exec -i --user postgres -e PGCLIENTENCODING=UTF8 -e PGPASSWORD "$container" "$@"
}
as_admin() {
    if [ "$mode" != container ]; then
        psql -X -w -v ON_ERROR_STOP=1 -U "$admin" "$@"
    else
        in_postgres psql -X -w -v ON_ERROR_STOP=1 -U "$admin" "$@"
    fi
}

for library in "$@"; do
    if [ "$control" = "$library" ]; then printf 'Baza rejestru musi być osobna od biblioteki.\n' >&2; exit 2; fi
    as_admin -d "$library" -c 'SELECT current_database();' >/dev/null
done

if [ "$mode" = remote ]; then
    server_version=$(as_admin -d "$control" -Aqt -c "SELECT current_setting('server_version_num') WHERE (SELECT rolsuper FROM pg_roles WHERE rolname=current_user)")
    if [ "${server_version:-0}" -lt 130000 ]; then printf 'Instalacja wymaga superużytkownika PostgreSQL 13 lub nowszego.\n' >&2; exit 2; fi
    hba_order=line_number
    if [ "$server_version" -ge 160000 ]; then hba_order=rule_number; fi
    for library in "$@"; do
        result=$(as_admin -d "$control" -Aqt -v "control_database=$control" -v "library=$library" -v "hba_order=$hba_order" < sql/verify-hba.sql)
        if [ "$result" != t ]; then
            printf 'Wgraj reguły pg_hba.conf dla %s i przeładuj konfigurację przed instalacją.\n' "$library" >&2
            exit 2
        fi
    done
fi

secret() { od -An -N32 -tx1 /dev/urandom | tr -d ' \n'; }
if [ "$mode" != managed ] && [ ! -f "$config" ]; then
    ( set -C
      printf 'PANEL_DB_PASSWORD=%s\nPANEL_ADMIN_PASSWORD=%s\nPANEL_SESSION_KEY=%s\nPANEL_SECURE_COOKIE=0\n' \
          "$(secret)" "$(secret)" "$(secret)" > "$config" )
fi
if [ "$mode" = managed ]; then
    agent_password=${PANEL_AGENT_PASSWORD:?Brak hasła konta technicznego}
else
    agent_password=$(sed -n 's/^PANEL_DB_PASSWORD=//p' "$config")
fi
case "$agent_password" in ''|*[!0-9a-f]*) printf '%s\n' 'PANEL_DB_PASSWORD musi mieć format 64 znaków szesnastkowych.' >&2; exit 2 ;; esac
test "${#agent_password}" -eq 64

# Keep the agent password out of the argument list and SQL file on disk.
{
    printf "\\\\set agent_password '%s'\n" "$agent_password"
    cat sql/control.sql
} | as_admin -d "$control" >/dev/null

for library in "$@"; do
    as_admin -d "$library" < sql/library.sql >/dev/null
    as_admin -d "$control" -v "library=$library" < sql/register.sql >/dev/null
    printf 'Dodano bibliotekę %s.\n' "$library"
done

case "$mode" in
    managed) sh sql/install-hba.sh "$admin" "$control" ;;
    container) in_postgres sh -s -- "$admin" "$control" < sql/install-hba.sh ;;
esac
if [ "$mode" = managed ]; then
    printf '%s\n' 'Panel jest gotowy do połączenia.'
else
    printf 'Panel może się teraz połączyć. Hasło administratora panelu zapisano w %s.\n' "$config"
fi
