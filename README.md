# DaVinci Resolve Project Server

[English](README.md) · [Polski](README.pl.md)

Host a DaVinci Resolve project library on your own computer or NAS so multiple workstations can use it. Docker runs PostgreSQL, scheduled backups, and pgAdmin. Add the optional **DaVinci Project Manager** web panel to manage user accounts and library access.

| What you want to install | Start here |
| --- | --- |
| PostgreSQL, scheduled backups, and pgAdmin | [View the base Compose file](davinci-resolve-project-server.yml) |
| The same stack with a web panel for managing access | [View the Compose file with the web panel](davinci-resolve-project-server-with-manager.yml) |
| A stack you can build and customize locally | [Install from the repository ZIP](#first-run-from-the-repository) |

[Single-file installation](#single-file-installation) · [Manage access in a browser](#manage-library-access-in-a-browser) · [Unraid web panel](#unraid-community-apps) · [Settings](#settings) · [Troubleshooting](#troubleshooting)

## Single-file installation

1. Open the Compose file you chose in the table above. On GitHub, use the copy button above the code to copy the whole file.
2. Create and name a stack in your stack editor, then paste the contents.
3. Set the environment variables listed below.
4. Deploy the stack. Docker pulls the images and, if you chose the web panel, builds it from the source pinned in the Compose file.

From a terminal, save the Compose file as `compose.yml`, put the settings in the `.env` file beside it, and run `docker compose up -d`.

| Variable | What to enter |
| --- | --- |
| `POSTGRES_PASSWORD` | Password for the `postgres` account you will use in Resolve. |
| `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD` | Email and a separate password for pgAdmin. |
| `POSTGRES_BIND_IP` | LAN or VPN address of the Docker host, for example `192.168.1.50`. The default `127.0.0.1` gives access from the same computer. |
| `RESOLVE_LIBRARY` | The library name you will enter in Resolve. The default is `studio`. |
| `PANEL_ADMIN_PASSWORD` | Password for the web panel’s `admin` account. Use a separate password of at least 8 characters. |
| `PANEL_DB_USER` | PostgreSQL login used by the web panel. Defaults to `resolve_panel_agent`. |
| `POSTGRES_VERSION` | Optional. Use `16`, `17`, or `18`. The default is `18`. |

In DaVinci Resolve, choose **Network → Add Project Library → Create**, enter the Docker host address, and use the name set in `RESOLVE_LIBRARY`. Scheduled backups use that name by default. Set `BACKUP_DATABASES` to back up a different library or a list of libraries.

PostgreSQL uses TCP port `5432`. To open pgAdmin in a browser, use the address in `POSTGRES_BIND_IP` and port `3001` by default.

Data and backups are stored in Docker volumes by default. To store backups in a directory on your NAS, set `BACKUP_DIR` to its absolute path. For an existing database, take a backup and restore it to the new stack.

<a name="optional-web-panel"></a>

### Manage library access in a browser

The DaVinci Project Manager web panel runs on your Docker server. From a browser, you can create accounts, reset passwords and choose which libraries each person can access. People open their projects in DaVinci Resolve. The base Compose file is enough to host a library.

1. Choose the [Compose file with the web panel](davinci-resolve-project-server-with-manager.yml) and set `PANEL_ADMIN_PASSWORD`. The panel reads its database connection settings from Compose. Python is included in the container.
2. In Resolve, create the library named in `RESOLVE_LIBRARY`. The `panel-setup` container registers it with the panel.
3. With the default settings, open the [local panel](http://127.0.0.1:3012) on the Docker host. If you set `POSTGRES_BIND_IP` to your NAS address, use that address in your browser, for example `http://192.168.1.50:3012`. Sign in as `admin` with the password you set in `PANEL_ADMIN_PASSWORD`.

The panel opens in English. You can choose Polish on the sign-in page or later in the sidebar.

Connect the desktop app to the same account registry to see the same accounts and library assignments. Create groups in the desktop app. The web panel shows which group grants access, even after you remove a direct assignment. [Set up user groups in the desktop app](https://github.com/LukaszOn/davinci-project-manager/blob/main/GUIDE.md#user-groups)

### Connect the desktop Manager

In **Connections**, enter the same host address and port `5432` you use for Resolve. Sign in with your PostgreSQL login and password. In **Connection options**, leave **Connection database** set to `postgres`. The Compose files ship without a TLS certificate. On a trusted LAN or private VPN, select **Prefer TLS** for this setup. If you configured a server certificate, use **Verify TLS** with the hostname on the certificate.

Once connected, select the library you created in Resolve. [DaVinci Project Manager releases](https://github.com/LukaszOn/davinci-project-manager/releases)

## First run from the repository

Open the [repository on GitHub](https://github.com/LukaszOn/davinci-resolve-project-server), choose **Code → Download ZIP**, and extract the full directory on the Docker host. This setup also uses files in the subdirectories.

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
| `RESOLVE_LIBRARY` | Enter the library name you will use in Resolve, for example `editing_projects`. The default is `studio`. Set `BACKUP_DATABASES` to override it or back up several libraries. |

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
| **Name** | The exact name you set in `RESOLVE_LIBRARY`. |
| **Location** | Docker host address, for example `127.0.0.1` or your NAS address. |
| **Username** | `POSTGRES_USER` from `.env`. The default is `postgres`. |
| **Password** | `POSTGRES_PASSWORD` from `.env`. |

Select **Create**, then create and save a test project. To open an existing library, use **Connect** and enter its exact name and credentials for an account with access. [Resolve documentation at Blackmagic Design Support](https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion)

The ZIP stack also creates an initial database called `database`. The backup schedule uses `RESOLVE_LIBRARY`. If you previously relied on `POSTGRES_DB` to choose what gets backed up, set `BACKUP_DATABASES` to that exact name before updating.

### 4. Check the first backup

For one library, check that `RESOLVE_LIBRARY` matches its name in Resolve. For several libraries, set a comma-separated list, for example `BACKUP_DATABASES=editing_projects,sound_projects`. Apply the settings and run a backup.

```sh
docker compose up -d pgbackups
docker compose exec -T pgbackups /backup.sh
```

When you see `SQL backup created successfully`, check `backups/last/` for the library's `.backup` file. Backups run daily at **02:30 UTC** by default. To check the backup, restore it on a separate instance and open a project in Resolve. The archive contains the selected library. To recover team access as well, plan for PostgreSQL roles, the Manager account registry in `postgres` and the library access rules. Keep a separate backup of your media.

## Recover a server with its accounts

The scheduled archive lets you restore one library in Manager. For a self-hosted server, a physical PostgreSQL backup also preserves role passwords, groups and library registrations across the whole instance.

1. From a trusted backup host, use the PostgreSQL tools for your server's major version. The backup login needs replication permission and a matching replication entry in `pg_hba.conf`. Replace the example host and login below. Choose an empty destination. The example assumes all data is under `PGDATA`.
2. Run these commands and keep the verified copy on separate storage with restricted access.

```sh
pg_basebackup -h db.example.internal -U backup_operator -D studio-cluster -Fp -X stream -P -W
pg_verifybackup studio-cluster
```

3. For a recovery drill, **copy** the verified directory into a fresh, empty data volume. Give the PostgreSQL operating-system user ownership and start the same PostgreSQL major version on a compatible platform, on an isolated address. Preserve the directory layout expected by `PGDATA`. Save any external PostgreSQL configuration, Compose settings, panel secrets and media separately.
4. Open a project with an existing user account. Save a change, open a library assigned through a group and check that the server denies access to an unassigned library. Check that the original server still has the original project.

## Service addresses

| Tool | Where to open it | Credentials |
| --- | --- | --- |
| DaVinci Resolve | **Network** libraries on PostgreSQL port **5432**. | PostgreSQL username and password. |
| pgAdmin | [http://127.0.0.1:3001](http://127.0.0.1:3001) on the Docker host. | `PGADMIN_DEFAULT_*` from `.env`. |
| DaVinci Project Manager web panel | [http://127.0.0.1:3012](http://127.0.0.1:3012) after adding the panel. | The username is `admin`. For a single-file install, use `PANEL_ADMIN_PASSWORD` from the stack settings. For a ZIP install, use the password in `panel/.env`. |

To open pgAdmin from another computer on a trusted LAN, set `PGADMIN_BIND_IP` to the Docker host's LAN address. Run `docker compose up -d pgadmin` and open that address on port `3001`. Enter the PostgreSQL password when opening the **DaVinci Resolve** connection in pgAdmin.

## Add the panel to a server installed from the repository ZIP

Use these steps if your server already runs from the repository’s `docker-compose.yml` and you want to add the panel. The single-file setup with the web panel does this automatically.

<details>
<summary>Commands for an existing repository installation</summary>

Starting with a working library from step 3, open the repository directory in a terminal with `sh`, Python 3, and access to the same Docker host. Replace `editing_projects` with the exact name of the existing library.

```sh
python3 panel/configure.py init --db-host postgres --title 'DaVinci Project Manager' --output panel/.env

PANEL_ENV_FILE=.env \
  PANEL_POSTGRES_CONTAINER="$(docker compose ps -q postgres)" \
  PANEL_POSTGRES_ADMIN="$(docker compose exec -T postgres printenv POSTGRES_USER)" \
  sh panel/install-db.sh editing_projects

docker compose -f docker-compose.yml -f compose.panel.yml up -d --build
```

The panel credentials are in `panel/.env`. To register another library, run `install-db.sh` with its name.

Open the panel on port `3012`. To change the address or port, update `PANEL_BIND_IP` or `PANEL_PORT` in the main `.env` and run the command with both Compose files again. For a panel behind an HTTPS proxy, set `PANEL_SECURE_COOKIE=1` in `panel/.env`.

</details>

<details>
<summary>Testing local changes to the panel source</summary>

In a full checkout, add `PANEL_BUILD_CONTEXT=./panel` and `PANEL_IMAGE=davinci-project-manager-web:local` to the settings for the single-file stack with the panel. Then run `docker compose -f davinci-resolve-project-server-with-manager.yml up -d --build` to build the image from your local source.

</details>

## Unraid Community Apps

The web panel connects to PostgreSQL and uses the access module to manage Resolve libraries.

To install the module in a PostgreSQL container, run this command from the repository directory. Substitute your container and library names.

```sh
PANEL_POSTGRES_CONTAINER=your-postgres \
  PANEL_ENV_FILE="$PWD/panel/.env" \
  sh panel/install-db.sh editing_projects
```

The installer writes the connection settings to `panel/.env`. Set `PANEL_DB_USER` to choose the panel login or `PANEL_POSTGRES_ADMIN` to specify the PostgreSQL administrator login.

If **DaVinci Project Manager** is listed in **Apps**, select **Install**. To install it manually, open the [Unraid XML template](templates/davinci-project-manager.xml) on GitHub. Choose **Download raw file**, save it in `/boot/config/plugins/dockerMan/templates-user/`, and select it under **Docker → Add Container**.

In the Unraid template, enter the server address under **PostgreSQL host**. Copy `PANEL_DB_USER` and `PANEL_DB_PASSWORD` from `panel/.env` into **PostgreSQL service account** and **PostgreSQL service password**.

Set **Panel administrator password** to a password of at least 8 characters. Open **WebUI** and sign in as `admin`.

### Access backup files on Unraid

Set `BACKUP_DIR` in the Project Server stack to the directory for library backups.

You'll find `.backup` files in the `last/` subdirectory of your chosen folder. If you share `backups` over SMB, you can open it from Windows, for example at `\\UNRAID\backups\davinci-resolve\last`. Copy a dated archive for the library you want to restore.

Sign in to the destination PostgreSQL server as an administrator and create an empty database with the name you want. If you use pgAdmin in a browser, upload the file to **My Storage** through **Tools → Storage Manager**. Right-click the new database, choose **Restore**, set the format to **Custom or tar**, and select the `.backup` file. Under **Query Options**, leave **Include CREATE DATABASE statement** off to restore into the selected database. [Restore in pgAdmin](https://www.pgadmin.org/docs/pgadmin4/latest/restore_dialog.html)

If the destination server is missing roles from the source, turn on **Owner** and **Privileges** under **Data Options → Do not save** to skip ownership and permissions. To manage access to the restored library from the web panel, register it on the destination server.

For a new PostgreSQL installation, you can set the data directory in the same stack, for example `POSTGRES_DATA_DIR=/mnt/user/appdata/davinci-resolve/postgres`.

## Settings

| Variable | Default and purpose |
| --- | --- |
| `POSTGRES_VERSION` | `18`. You can use `16` or `17`. The backup container uses the same version. |
| `POSTGRES_USER`, `POSTGRES_DB` | `postgres` and `database`. Used for the initial database setup. |
| `POSTGRES_DATA_DIR` | `./data/postgres-<major>` on the host. PostgreSQL stores data under `<major>/docker` inside it. |
| `BACKUP_DIR`, `BACKUP_DATABASES` | Backup directory (default `./backups` for the ZIP stack) and optional list of databases. An empty list uses `RESOLVE_LIBRARY`. |
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

This project is an independent fork of [Elliot Matson’s Docker-Davinci-Resolve-Project-Server](https://github.com/elliotmatson/Docker-Davinci-Resolve-Project-Server) under the [MIT license](LICENSE).
