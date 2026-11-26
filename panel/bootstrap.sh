#!/bin/sh
set -eu

secrets_dir=/run/resolve-panel

case "${1:-}" in
    serve)
        attempts=0
        until [ -r "$secrets_dir/agent-password" ] && [ -r "$secrets_dir/session-key" ]; do
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 60 ]; then
                printf '%s\n' 'Panel czeka na sekrety. Sprawdź logi usługi panel-setup.' >&2
                exit 1
            fi
            sleep 1
        done
        exec /venv/bin/gunicorn --bind=0.0.0.0:8080 --workers=1 --threads=4 --worker-tmp-dir=/tmp --no-control-socket app:app
        ;;
    configure)
        umask 077
        chmod 0711 "$secrets_dir"
        for name in agent-password session-key; do
            destination="$secrets_dir/$name"
            if [ ! -e "$destination" ]; then
                temporary=$(mktemp "$secrets_dir/.secret.XXXXXX")
                od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$temporary"
                test "$(wc -c < "$temporary")" -eq 64
                chown 10001:10001 "$temporary"
                mv "$temporary" "$destination"
            fi
        done
        PANEL_AGENT_PASSWORD=$(cat "$secrets_dir/agent-password")
        export PANEL_AGENT_PASSWORD
        exec gosu postgres sh /panel/bootstrap.sh register
        ;;
    register)
        library=${RESOLVE_LIBRARY:?Podaj nazwę biblioteki w RESOLVE_LIBRARY}
        case "$library" in
            *[!a-zA-Z0-9_]*|postgres|template0|template1)
                printf '%s\n' 'RESOLVE_LIBRARY musi być nazwą biblioteki (litery ASCII, cyfry i podkreślenia).' >&2
                exit 2
                ;;
        esac
        test "${#library}" -le 63
        export PGCONNECT_TIMEOUT=5
        query() { psql -XAtw -v ON_ERROR_STOP=1 -d postgres "$@"; }
        library_exists() {
            query -v "library=$library" <<'SQL'
SELECT EXISTS (SELECT FROM pg_database WHERE datname = :'library' AND datallowconn AND NOT datistemplate);
SQL
        }
        printf 'Czekam na bibliotekę %s. Utwórz ją w DaVinci Resolve albo odtwórz z kopii.\n' "$library"
        while [ "$(library_exists)" != t ]; do sleep 5; done

        agent_exists=$(query -c "SELECT EXISTS (SELECT FROM pg_roles WHERE rolname = 'resolve_panel_agent')")
        if [ "$agent_exists" = t ]; then
            if ! PGPASSWORD="$PANEL_AGENT_PASSWORD" query -U resolve_panel_agent -c 'SELECT 1' >/dev/null 2>&1; then
                printf '%s\n' 'Baza ma już konto techniczne panelu z innym hasłem. Użyj woluminu sekretów tej instalacji.' >&2
                exit 1
            fi
        fi
        exec sh /panel/install-db.sh --managed-volume "$library"
        ;;
    *)
        exit 2
        ;;
esac
