import argparse
import hashlib
from ipaddress import ip_address, ip_network
import os
from pathlib import Path
import re
import secrets


def database(value):
    if not re.fullmatch(r'[a-zA-Z0-9_]{1,63}', value) or value in {'template0', 'template1'}:
        raise argparse.ArgumentTypeError('Use 1–63 ASCII letters, digits, or underscores.')
    return value


def port(value):
    number = int(value)
    if not 1 <= number <= 65535:
        raise argparse.ArgumentTypeError('Use a port in the range 1–65535.')
    return number


def address(value):
    if value == 'all':
        return value
    try:
        return str(ip_network(value, strict=False))
    except ValueError as error:
        raise argparse.ArgumentTypeError('Enter an IP address, CIDR subnet, or all.') from error


def compose_literal(value):
    if any(ord(character) < 32 for character in value):
        raise ValueError('Configuration values cannot contain control characters.')
    return "'" + value.replace('\\', '\\\\').replace("'", "\\'") + "'"


def initialize(args):
    if not re.fullmatch(r'[a-zA-Z0-9_.:-]+', args.db_host):
        raise ValueError('Enter a PostgreSQL hostname or single IP address.')
    if not re.fullmatch(r'[a-z0-9][a-z0-9_-]*', args.project):
        raise ValueError('Use lowercase letters, digits, hyphens, and underscores in the Compose project name.')
    if not 1 <= len(args.title.strip()) <= 80:
        raise ValueError('Use 1–80 characters for the panel name.')

    binding = ip_address(args.bind)
    path = args.output
    settings = {
        'PANEL_PROJECT_NAME': args.project, 'PANEL_DISPLAY_NAME': compose_literal(args.title.strip()),
        'PANEL_BIND_IP': f'[{binding}]' if binding.version == 6 else str(binding),
        'PANEL_PORT': args.port,
        'PANEL_SECURE_COOKIE': int(args.https),
        'PANEL_DB_HOST': args.db_host, 'PANEL_DB_PORT': args.db_port, 'PANEL_DB_NAME': args.control_db,
        'PANEL_DB_USER': 'resolve_panel_agent', 'PANEL_DB_SSLMODE': args.sslmode,
        'PANEL_DB_PASSWORD': secrets.token_hex(32), 'PANEL_ADMIN_PASSWORD': secrets.token_hex(32),
        'PANEL_SESSION_KEY': secrets.token_hex(32),
    }
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8', newline='\n') as config:
        for name, value in settings.items():
            config.write(f'{name}={value}\n')
    print(f'Saved {path}. The panel password is in PANEL_ADMIN_PASSWORD.')


def hba(args):
    if args.control_db in args.libraries:
        raise ValueError('Use a separate database for the account registry.')
    remote = 'hostssl' if args.ssl else 'host'
    print('# Insert the rules above the general PostgreSQL login rules.')
    print(f'local "{args.control_db}" resolve_panel_agent scram-sha-256')
    print(f'{remote} "{args.control_db}" resolve_panel_agent {args.panel_from} scram-sha-256')
    for library in dict.fromkeys(args.libraries):
        group = 'resolve_lib_' + hashlib.md5(library.encode('ascii'), usedforsecurity=False).hexdigest()
        print(f'local "{library}" +{group} scram-sha-256')
        print(f'{remote} "{library}" +{group} {args.members_from} scram-sha-256')
    print('local all resolve_panel_agent,+resolve_panel_members reject')
    print('host all resolve_panel_agent,+resolve_panel_members all reject')


def main():
    parser = argparse.ArgumentParser(description='Konfiguracja Project Library Desk dla Docker Compose.')
    actions = parser.add_subparsers(required=True)
    init = actions.add_parser('init', help='Create a new .env file with generated passwords.')
    init.add_argument('--db-host', required=True)
    init.add_argument('--db-port', type=port, default=5432)
    init.add_argument('--control-db', type=database, default='postgres')
    init.add_argument('--sslmode', choices=('disable', 'prefer', 'require', 'verify-ca', 'verify-full'), default='prefer')
    init.add_argument('--bind', default='127.0.0.1')
    init.add_argument('--port', type=port, default=3012)
    init.add_argument('--https', action='store_true', help='Connect to the panel over HTTPS.')
    init.add_argument('--title', default='Project Library Desk')
    init.add_argument('--project', default='project-library-desk')
    init.add_argument('--output', type=Path, default=Path('.env'))
    init.set_defaults(run=initialize)

    rules = actions.add_parser('hba', help='Print pg_hba.conf rules for the selected libraries.')
    rules.add_argument('libraries', nargs='+', type=database)
    rules.add_argument('--control-db', type=database, default='postgres')
    rules.add_argument('--panel-from', type=address, default='all')
    rules.add_argument('--members-from', type=address, default='all')
    rules.add_argument('--ssl', action='store_true')
    rules.set_defaults(run=hba)

    args = parser.parse_args()
    try:
        args.run(args)
    except FileExistsError as error:
        parser.exit(2, f'The file already exists. Keep it or choose a different path: {error.filename}\n')
    except (ValueError, OSError) as error:
        parser.exit(2, f'{error}\n')


if __name__ == '__main__':
    main()
