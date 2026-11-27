#!/bin/sh
set -eu

secrets_dir=/run/resolve-panel

case "${1:-}" in
    serve)
        attempts=0
        until [ -r "$secrets_dir/agent-user" ] && [ -r "$secrets_dir/agent-password" ] && [ -r "$secrets_dir/session-key" ] &&
              { configured_user=$(cat "$secrets_dir/agent-user") && [ "$configured_user" = "${PANEL_DB_USER:-$configured_user}" ]; }; do
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 60 ]; then
                printf '%s\n' 'Waiting for the configured panel account and credentials. Check the panel-setup logs.' >&2
                exit 1
            fi
            sleep 1
        done
        export PANEL_DB_USER="$configured_user"
        exec /venv/bin/gunicorn --bind=0.0.0.0:8080 --workers=1 --threads=4 --worker-tmp-dir=/tmp --no-control-socket app:app
        ;;
    configure)
        umask 077
        chmod 0711 "$secrets_dir"
        . /panel/sql/render-layout.sh
        layout=$(gosu postgres psql -XAtqw -v ON_ERROR_STOP=1 -d postgres -f /panel/sql/registry-layout.sql)
        check_layout "$layout"
        installed_user=$(render_layout "$layout" /panel/sql/installed-agent.sql | gosu postgres psql -XAtqw -v ON_ERROR_STOP=1 -d postgres)
        export PANEL_DB_USER="${PANEL_DB_USER:-${installed_user:-resolve_panel_agent}}"
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
        publish_user() {
            temporary=$(mktemp "$secrets_dir/.agent-user.XXXXXX")
            printf '%s\n' "$PANEL_DB_USER" > "$temporary"
            chown 10001:10001 "$temporary"
            mv "$temporary" "$secrets_dir/agent-user"
        }
        if [ -n "$installed_user" ] && [ "$installed_user" != "$PANEL_DB_USER" ]; then
            gosu postgres sh /panel/bootstrap.sh register
            publish_user
            exit 0
        fi
        # Serve the login page while a fresh stack waits for its first library.
        publish_user
        exec gosu postgres sh /panel/bootstrap.sh register
        ;;
    register)
        library=${RESOLVE_LIBRARY:?Set the library name in RESOLVE_LIBRARY}
        case "$library" in
            *[!a-zA-Z0-9_]*|postgres|template0|template1)
                printf '%s\n' 'Use ASCII letters, digits, and underscores in RESOLVE_LIBRARY.' >&2
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
        printf 'Waiting for library %s. Create it in DaVinci Resolve or restore it from a backup.\n' "$library"
        while [ "$(library_exists)" != t ]; do sleep 5; done

        exec sh /panel/install-db.sh --managed-volume "$library"
        ;;
    *)
        exit 2
        ;;
esac
