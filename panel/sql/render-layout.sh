# Expand the module's own SQL identifiers for an existing installation.
# New installations use the checked-in names unchanged.
check_layout() {
    case "$1" in
        ''|[!a-z]*|*[!a-z0-9_]*) printf '%s\n' 'Unable to identify a trusted access registry.' >&2; return 1 ;;
    esac
    test "${#1}" -le 26
}

render_layout() {
    check_layout "$1" || return 1
    sed -E "s/resolve_(library_access|access|lib_|panel_|share_new_objects)/${1}_\\1/g" "$2"
}
