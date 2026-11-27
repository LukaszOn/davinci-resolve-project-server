#!/bin/sh
set -eu

if [ -z "${PANEL_SESSION_KEY:-}" ] && [ -z "${PANEL_SESSION_KEY_FILE:-}" ]; then
    PANEL_SESSION_KEY=$(python -c 'import secrets; print(secrets.token_hex(32))')
    export PANEL_SESSION_KEY
fi

exec "$@"
