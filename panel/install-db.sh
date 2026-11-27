#!/bin/sh
set -eu
umask 077
cd "$(dirname "$0")"
. ./sql/render-layout.sh

mode=container
if [ "${1:-}" = --remote ]; then mode=remote; shift; fi
if [ "${1:-}" = --managed-volume ]; then mode=managed; shift; fi
if [ "$#" -eq 0 ]; then
    printf '%s\n' 'Usage: sh install-db.sh [--remote] LIBRARY [LIBRARY ...]' >&2
    exit 2
fi
for library in "$@"; do
    case "$library" in
        ''|*[!a-zA-Z0-9_]*|postgres|template0|template1) printf 'Invalid library name: %s\n' "$library" >&2; exit 2 ;;
    esac
    if [ "${#library}" -gt 63 ]; then printf 'The library name is too long.\n' >&2; exit 2; fi
done

if [ "$mode" = container ]; then
    container=${PANEL_POSTGRES_CONTAINER:?Set PANEL_POSTGRES_CONTAINER to the PostgreSQL container name}
fi
admin=${PANEL_POSTGRES_ADMIN:-postgres}
config=${PANEL_ENV_FILE:-panel.env}
if [ "$mode" != container ]; then
    admin=${PGUSER:-postgres}
    export PGCLIENTENCODING=UTF8
    : "${PGHOST:?Set PGHOST for the administrative connection}"
fi
if [ "$mode" = remote ]; then
    config=${PANEL_ENV_FILE:-.env}
    test -f "$config"
fi
if [ "$mode" != managed ] && [ -L "$config" ]; then config=$(readlink -f "$config"); fi
control_from_file=''
user_from_file=''
if [ "$mode" != managed ] && [ -f "$config" ]; then
    control_from_file=$(sed -n 's/^PANEL_DB_NAME=//p' "$config")
    user_from_file=$(sed -n 's/^PANEL_DB_USER=//p' "$config" | tail -n 1)
fi
control=${PANEL_CONTROL_DATABASE:-${control_from_file:-postgres}}
case "$control" in ''|*[!a-zA-Z0-9_]*|template0|template1) printf 'Invalid account registry database name.\n' >&2; exit 2 ;; esac
in_postgres() {
    docker exec -i --user postgres -e PGCLIENTENCODING=UTF8 -e PGPASSWORD -e PGPASSFILE -e PGREQUIREAUTH "$container" "$@"
}
sql() {
    if [ "$mode" != container ]; then
        psql -X -w -v ON_ERROR_STOP=1 "$@"
    else
        in_postgres psql -X -w -v ON_ERROR_STOP=1 "$@"
    fi
}
as_admin() { sql -U "$admin" "$@"; }
installed_agent() { render_layout "$layout" sql/installed-agent.sql | as_admin -d "$control" -Aqt; }
install_rules() {
    if [ "$mode" = remote ]; then return; fi
    expected_user=$1
    while :; do
        if [ "$mode" = managed ]; then
            sh sql/install-hba.sh "$admin" "$control" "$layout" "$@"
        else
            in_postgres sh -s -- "$admin" "$control" "$layout" "$@" < sql/install-hba.sh
        fi
        # A concurrent installer may have renamed the account while writing the file.
        current_user=$(installed_agent)
        if [ "$current_user" = "$1" ]; then break; fi
        if [ -z "$current_user" ]; then printf '%s\n' 'The installed service account disappeared.' >&2; return 1; fi
        set -- "$current_user"
    done
    if [ "$current_user" != "$expected_user" ]; then
        printf 'Another installation changed PANEL_DB_USER to %s. Retry with the current configuration.\n' "$current_user" >&2
        return 1
    fi
}

if [ "$mode" = remote ]; then
    server_version=$(as_admin -d "$control" -Aqt -c "SELECT current_setting('server_version_num') WHERE (SELECT rolsuper FROM pg_roles WHERE rolname=current_user)")
    if [ "${server_version:-0}" -lt 130000 ]; then printf 'Installation requires a superuser on PostgreSQL 13 or later.\n' >&2; exit 2; fi
fi
layout=$(as_admin -d "$control" -Aqt < sql/registry-layout.sql)
check_layout "$layout"
installed_user=$(installed_agent)
agent=${PANEL_DB_USER:-${installed_user:-${user_from_file:-resolve_panel_agent}}}
case "$agent" in
    ''|[!a-z]*|*[!a-z0-9_]*|pg_*|"${layout}_panel_members"|"${layout}_lib_"*|postgres|public|all|replication|sameuser|samerole|samegroup|none|current_user|current_role|session_user)
        printf '%s\n' 'PANEL_DB_USER must be a non-reserved lowercase PostgreSQL login (letters, digits, underscores; start with a letter).' >&2
        exit 2 ;;
esac
if [ "${#agent}" -gt 63 ] || [ "$agent" = "$admin" ]; then
    printf '%s\n' 'PANEL_DB_USER must fit in 63 characters and differ from the installation administrator.' >&2
    exit 2
fi
if [ "$installed_user" != "$agent" ]; then
    available=$(as_admin -d "$control" -Aqt -v "requested=$agent" -v "installed=$installed_user" -v "schema=${layout}_access" <<'SQL'
SELECT NOT EXISTS (
    SELECT FROM pg_authid r WHERE r.rolname = :'requested' AND NOT (
        :'installed' = '' AND r.rolpassword IS NULL
        AND r.rolcanlogin AND NOT (r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolreplication OR r.rolbypassrls)
        AND EXISTS (SELECT FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
                    WHERE p.oid = to_regprocedure(format('%I.panel_administrator(text)', :'schema'))
                      AND a.grantee = r.oid AND r.oid <> p.proowner AND a.privilege_type = 'EXECUTE')
    )
);
SQL
)
    if [ "$available" != t ]; then
        printf 'Role "%s" already exists. Choose a different PANEL_DB_USER.\n' "$agent" >&2
        exit 2
    fi
fi

for library in "$@"; do
    if [ "$control" = "$library" ]; then printf 'Use a separate database for the account registry.\n' >&2; exit 2; fi
    as_admin -d "$library" -c 'SELECT current_database();' >/dev/null
done

if [ "$mode" = remote ]; then
    hba_order=line_number
    if [ "$server_version" -ge 160000 ]; then hba_order=rule_number; fi
    for library in "$@"; do
        result=$(render_layout "$layout" sql/verify-hba.sql | as_admin -d "$control" -Aqt -v "agent_user=$agent" -v "control_database=$control" -v "library=$library" -v "hba_order=$hba_order")
        if [ "$result" != t ]; then
            printf 'Generate rules for %s with configure.py hba --detect-layout, add them to pg_hba.conf, then reload PostgreSQL.\n' "$library" >&2
            exit 2
        fi
    done
fi

secret() { od -An -N32 -tx1 /dev/urandom | tr -d ' \n'; }
if [ "$mode" != managed ] && [ ! -f "$config" ]; then
    if [ -n "$installed_user" ]; then
        printf 'Use PANEL_ENV_FILE to provide the existing configuration and password for %s.\n' "$installed_user" >&2
        exit 2
    fi
    ( set -C
      printf 'PANEL_DB_USER=%s\nPANEL_DB_PASSWORD=%s\nPANEL_ADMIN_PASSWORD=%s\nPANEL_SESSION_KEY=%s\nPANEL_SECURE_COOKIE=0\n' \
          "$agent" "$(secret)" "$(secret)" "$(secret)" > "$config" )
    user_from_file=$agent
fi
if [ "$mode" = managed ]; then
    agent_password=${PANEL_AGENT_PASSWORD:?The service account password is missing}
else
    agent_password=$(sed -n 's/^PANEL_DB_PASSWORD=//p' "$config")
fi
case "$agent_password" in ''|*[!0-9a-f]*) printf '%s\n' 'PANEL_DB_PASSWORD must contain 64 hexadecimal characters.' >&2; exit 2 ;; esac
test "${#agent_password}" -eq 64
if [ -n "$installed_user" ]; then
    # Restore the installed login's SCRAM rules even after an interrupted update.
    install_rules "$installed_user"
    if PGPASSWORD= PGPASSFILE=/dev/null sql -U "$installed_user" -d "$control" -c 'SELECT 1' >/dev/null 2>&1; then
        printf 'A connection as %s succeeded without a password. Require SCRAM authentication before continuing.\n' "$installed_user" >&2
        exit 1
    fi
    if ! PGREQUIREAUTH=scram-sha-256 PGPASSWORD="$agent_password" sql -U "$installed_user" -d "$control" -c 'SELECT 1' >/dev/null; then
        printf 'Could not log in as %s. Use the existing panel database password and check its SCRAM connection rules.\n' "$installed_user" >&2
        exit 1
    fi
    if [ "$installed_user" != "$agent" ]; then
        install_rules "$installed_user" "$agent"
    fi
fi

# Keep the agent password out of the argument list and SQL file on disk.
if ! {
    printf "\\\\set agent_password '%s'\n" "$agent_password"
    render_layout "$layout" sql/control.sql
} | as_admin -d "$control" -v "agent_user=$agent" -v "verified_user=$installed_user" >/dev/null; then
    if [ -n "$installed_user" ] && [ "$installed_user" != "$agent" ]; then
        actual_user=$(installed_agent)
        if [ -n "$actual_user" ]; then install_rules "$actual_user"; fi
    fi
    exit 1
fi

for library in "$@"; do
    render_layout "$layout" sql/library.sql | as_admin -d "$library" >/dev/null
    render_layout "$layout" sql/register.sql | as_admin -d "$control" -v "library=$library" >/dev/null
    printf 'Added library %s.\n' "$library"
done

install_rules "$agent"
if [ "$mode" != managed ] && [ "$user_from_file" != "$agent" ]; then
    updated=$(mktemp "${config}.XXXXXX")
    trap 'rm -f "$updated"' EXIT
    awk -v agent="$agent" '!/^PANEL_DB_USER=/{print} END{print "PANEL_DB_USER=" agent}' "$config" > "$updated"
    mv -f "$updated" "$config"
fi
if [ "$mode" = managed ]; then
    printf '%s\n' 'The panel is ready to connect.'
else
    printf 'The panel can now connect. The panel administrator password is stored in %s.\n' "$config"
fi
