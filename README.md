# DaVinci Resolve Project Server

[English](README.md) · [Polski](README.pl.md)

Host a DaVinci Resolve project library on your own computer or NAS so multiple workstations can use it. Docker runs PostgreSQL, scheduled backups, and pgAdmin. Add the optional **DaVinci Project Manager** web panel to manage user accounts and library access.

[Single-file installation](#single-file-installation) · [First run from the repository](#first-run-from-the-repository) · [Settings](#settings) · [Troubleshooting](#troubleshooting)

## Single-file installation

Choose a complete Compose file for a new installation.

| Services | Compose file |
| --- | --- |
| PostgreSQL, backups, and pgAdmin | [Base stack](https://github.com/LukaszOn/davinci-resolve-project-server/releases/latest/download/davinci-resolve-project-server.yml) |
| PostgreSQL, backups, pgAdmin, and the web panel | [Stack with the web panel](https://github.com/LukaszOn/davinci-resolve-project-server/releases/latest/download/davinci-resolve-project-server-with-manager.yml) |

1. Create and name a stack in your stack editor, then paste the file you chose.
2. Set the environment variables listed below.
3. Deploy the stack. Docker pulls the images and builds the optional panel from the source pinned in the Compose file.

From a terminal, save the Compose file as `compose.yml`, put the settings in the `.env` file beside it, and run `docker compose up -d`.

| Variable | What to enter |
| --- | --- |
| `POSTGRES_PASSWORD` | Password for the `postgres` account you will use in Resolve. |
| `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD` | Email and a separate password for pgAdmin. |
| `POSTGRES_BIND_IP` | LAN or VPN address of the Docker host, for example `192.168.1.50`. The default `127.0.0.1` gives access from the same computer. |
| `RESOLVE_LIBRARY` | The library name you will enter in Resolve. The default is `studio`. |
| `PANEL_ADMIN_PASSWORD` | Only for the panel variant. Use a separate password of at least 32 characters. |
| `POSTGRES_VERSION` | Optional. Use `16`, `17`, or `18`. The default is `18`. |

In DaVinci Resolve, choose **Network → Add Project Library → Create**, enter the Docker host address, and use the name set in `RESOLVE_LIBRARY`. The server uses TCP port `5432`. Open pgAdmin at the host address on port `3001`.

For the panel variant, open the host address on port `3012`. Leave the username blank and enter `PANEL_ADMIN_PASSWORD`. Once the library appears in PostgreSQL, `panel-setup` registers it and exits. The panel receives the database address from Compose and uses its own service account. Scheduled backups use the same library name unless you set `BACKUP_DATABASES` separately.

Data and backups are stored in Docker volumes by default. To store backups in a directory on your NAS, set `BACKUP_DIR` to its absolute path. For an existing database, take a backup and restore it to the new stack.

## First run from the repository

[Download the repository ZIP](https://github.com/LukaszOn/davinci-resolve-project-server/archive/refs/heads/main.zip) or choose **Code → Download ZIP** on GitHub. Extract the full directory on the Docker host. Compose also uses files in its subdirectories.

| File | Purpose |
| --- | --- |
| [`docker-compose.yml`](docker-compose.yml) | Base stack with PostgreSQL, backups, and pgAdmin. |
| [`.env.example`](.env.example) | Example settings. Copy it to `.env` and fill in your values. |
| [`compose.panel.yml`](compose.panel.yml) | Adds the web panel to the base stack. |

### 1. Configure the stack

Open a terminal in the directory containing `docker-compose.yml` on the Docker host. Check that `docker compose version` returns a version. [Install Docker Compose](https://docs.docker.com/compose/install/)

On Linux, macOS, or a NAS terminal:

```sh
cp .env.example .env
```

On Windows PowerShell:

```powershell
Copy-Item -LiteralPath .env.example -Destination .env
```

Open `.env` in an editor. File managers may hide names beginning with a dot. On Windows, check that its full filename is `.env`.

| Setting | What to enter |
| --- | --- |
| `POSTGRES_PASSWORD` | Your PostgreSQL password for the first connection from Resolve. |
| `PGADMIN_DEFAULT_EMAIL` | The email address used to sign in to pgAdmin. |
| `PGADMIN_DEFAULT_PASSWORD` | A separate pgAdmin password. |
| `POSTGRES_BIND_IP` | The address Resolve uses to connect to the Docker host. |

Keep `.env` private because it contains passwords. Use single quotes around values that contain `$`. [Compose environment file syntax](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/#env-file-syntax)

| Where Resolve runs | `POSTGRES_BIND_IP` | Address in Resolve |
| --- | --- | --- |
| Same computer as Docker | `127.0.0.1` | `127.0.0.1` |
| Separate computer on the same LAN | LAN address of the Docker host, e.g. `192.168.1.50` | The same LAN address |
| Separate computer on a private VPN | VPN address of the Docker host | The same VPN address |

If Docker runs on a NAS and Resolve runs on your laptop, use the NAS address from its network settings or your router's device list. Allow TCP port `5432` on the trusted LAN or VPN if a firewall blocks it. [Docker port publishing](https://docs.docker.com/engine/network/port-publishing/)

### 2. Start the server

```sh
docker compose config --quiet
docker compose up -d --build --wait --wait-timeout 180
docker compose ps -a
```

Docker pulls the images and builds the pgAdmin setup helper on the first run. Expect `postgres`, `pgbackups`, and `pgadmin` to be running and `pgadmin-config` to show `Exited (0)`.

The repository stack stores PostgreSQL data under `./data` and backups under `./backups` by default. Use `docker compose stop` to stop services and keep their data.

### 3. Create a library in Resolve

In Resolve's **Project Manager**, open the library list and choose **Network → Add Project Library → Create**.

| Resolve field | Value |
| --- | --- |
| **Name** | A new library name, for example `studio_test`. |
| **Location** | Docker host address, for example `127.0.0.1` or your NAS address. |
| **Username** | `POSTGRES_USER` from `.env`. The default is `postgres`. |
| **Password** | `POSTGRES_PASSWORD` from `.env`. |

Select **Create**, then create and save a test project. To open an existing library, use **Connect** and enter its exact name and credentials for an account with access. [Blackmagic Design reference manual](https://documents.blackmagicdesign.com/UserManuals/DaVinciResolveReferenceManual.pdf)

PostgreSQL creates the initial `database` database during setup. Resolve creates the project library in this step.

### 4. Check the first backup

After creating the library, set `BACKUP_DATABASES=studio_test` in `.env`. Use comma-separated names for multiple libraries. Apply the change and run a backup.

```sh
docker compose up -d pgbackups
docker compose exec -T pgbackups /backup.sh
```

When you see `SQL backup created successfully`, check `backups/last/` for the library's `.backup` file. Backups run daily at **02:30 UTC** by default. They cover library data. Back up the video files and PostgreSQL roles separately.

## Service addresses

| Tool | Where to open it | Credentials |
| --- | --- | --- |
| DaVinci Resolve | **Network** libraries on PostgreSQL port **5432**. | PostgreSQL username and password. |
| pgAdmin | [http://127.0.0.1:3001](http://127.0.0.1:3001) on the Docker host. | `PGADMIN_DEFAULT_*` from `.env`. |
| DaVinci Project Manager web panel | [http://127.0.0.1:3012](http://127.0.0.1:3012) after adding the panel. | At first sign-in, leave the username blank and use `PANEL_ADMIN_PASSWORD`. |

To open pgAdmin from another computer on a trusted LAN, set `PGADMIN_BIND_IP` to the Docker host's LAN address. Run `docker compose up -d pgadmin` and open that address on port `3001`. Enter the PostgreSQL password when opening the **DaVinci Resolve** connection in pgAdmin.

## Optional web panel

The panel manages accounts and access in a browser. It can share the PostgreSQL instance and account registry with [DaVinci Project Manager for desktop](https://github.com/LukaszOn/davinci-project-manager). English is the default. Choose **Polski** on the sign-in page or in the sidebar to switch the browser's language.

<details>
<summary>Add the panel to the repository stack</summary>

Starting with a working library from step 3, open the repository directory in a terminal with `sh`, Python 3, and access to the same Docker host. Replace `studio_test` with the exact name of the existing library.

```sh
python3 panel/configure.py init --db-host postgres --title 'DaVinci Project Manager' --output panel/.env

PANEL_ENV_FILE=.env \
  PANEL_POSTGRES_CONTAINER="$(docker compose ps -q postgres)" \
  PANEL_POSTGRES_ADMIN="$(docker compose exec -T postgres printenv POSTGRES_USER)" \
  sh panel/install-db.sh studio_test

docker compose -f docker-compose.yml -f compose.panel.yml up -d --build
```

The first command generates passwords in `panel/.env`. Keep this file for upgrades. To add another library, run `install-db.sh` again with its name. The installer uses `psql` in the container and sets PostgreSQL access rules for managed accounts.

Open the panel on port `3012`. To change the address or port, update `PANEL_BIND_IP` or `PANEL_PORT` in the main `.env` and run the command with both Compose files again. For a panel behind an HTTPS proxy, set `PANEL_SECURE_COOKIE=1` in `panel/.env`.

</details>

## Settings

| Variable | Default and purpose |
| --- | --- |
| `POSTGRES_VERSION` | `18`. You can use `16` or `17`. The backup container uses the same version. |
| `POSTGRES_USER`, `POSTGRES_DB` | `postgres` and `database`. Used for the initial database setup. |
| `POSTGRES_DATA_DIR` | `./data/postgres-<major>` on the host. PostgreSQL stores data under `<major>/docker` inside it. |
| `BACKUP_DIR`, `BACKUP_DATABASES` | `./backups` and the list of libraries to back up. When the list is empty, the repository stack backs up `POSTGRES_DB`. |
| `TZ`, `BACKUP_SCHEDULE` | `UTC` and `30 2 * * *`. Set your timezone, for example `Europe/Warsaw`. |
| `BACKUP_KEEP_DAYS`, `BACKUP_KEEP_WEEKS`, `BACKUP_KEEP_MONTHS` | Retention periods. The defaults are 7 days, 4 weeks, and 6 months. |
| `PGADMIN_BIND_IP`, `PGADMIN_PORT` | `127.0.0.1` and `3001`. Interface and port for pgAdmin. |

Use PostgreSQL 18 for new installations when compatible with your Resolve version. The automated stack tests cover PostgreSQL 16, 17, and 18. Check your Resolve client by creating, opening, and saving a project in a test library. To upgrade PostgreSQL across major versions, keep the old data and restore a backup to a new instance. A data directory with `PG_VERSION` in its root uses the old layout. Choose a new directory for the migration. [Stack tests](https://github.com/LukaszOn/davinci-resolve-project-server/actions/workflows/stack-healthcheck.yml) · [PostgreSQL image documentation](https://hub.docker.com/_/postgres)

## Troubleshooting

| Problem | What to check |
| --- | --- |
| `no configuration file provided` | Run Compose from the directory containing `docker-compose.yml`. Extract the whole repository ZIP. |
| Compose asks for an environment variable | Check the `.env` filename and the required fields in step 1. |
| Resolve on another computer cannot connect | Check Docker's `POSTGRES_BIND_IP` and access to TCP port `5432` on that network. |
| Port 5432 is already in use | Check for another instance. Two instances on one host need separate IP addresses, Compose project names, and data directories. |
| Backups contain the `database` database | Set `BACKUP_DATABASES` to the library you created in Resolve and repeat step 4. |
| Backup reports `ln: … Operation not supported` | Set `BACKUP_DIR` to a local disk directory. Rotation uses hard and symbolic links. [Backup rotation](https://github.com/prodrigestivill/docker-postgres-backup-local#how-the-backups-folder-works) |
| PostgreSQL still accepts the old password | The `.env` password applies during initialization. On an existing server, change the password of the PostgreSQL role first, then update `.env`. |

Check service status with `docker compose ps -a`. Use `docker compose logs --tail 50 postgres pgbackups` to see the database and backup logs.

## Upstream project

This project is an independent fork of [Elliot Matson’s Docker-Davinci-Resolve-Project-Server](https://github.com/elliotmatson/Docker-Davinci-Resolve-Project-Server) under the [MIT license](LICENSE.md).
