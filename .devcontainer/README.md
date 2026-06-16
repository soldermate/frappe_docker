# Local Development Setup

This devcontainer setup runs Frappe's development stack (MariaDB, Redis, and the bench image) via Docker Compose. You can work entirely from the terminal or attach VS Code to the running container — both workflows are supported.

## Prerequisites

- [Colima](https://github.com/abiosoft/colima) (Docker runtime for Apple Silicon)
- [just](https://github.com/casey/just) (command runner)
- VS Code with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (optional)

## First-time setup

### 1. Start Colima

```sh
just colima
```

This starts the Colima VM (Apple Silicon, 4 CPU / 8 GB RAM / 60 GB disk) and sets the Docker context. Only needed once per machine boot — Colima persists until you shut it down or reboot.

### 2. Start the stack

```sh
just up
```

Starts MariaDB, Redis (cache + queue), and the frappe container in the background. The frappe container runs `sleep infinity` — it's a long-lived sandbox you exec into.

### 3. Create a bench and site

Enter the container:

```sh
just shell
```

Then inside the container:

```sh
cd /workspace/development
bench init --skip-redis-config-generation frappe-bench
cd frappe-bench
bench new-site --db-root-password 123 --admin-password admin --mariadb-user-host-login-scope=% development.localhost
# --mariadb-user-host-login-scope=% creates the DB user as db_user@% (any host) rather than
# db_user@<container-ip>, so the connection still works if the container IP changes after a restart
bench --site development.localhost set-config developer_mode 1
bench start
```

Your bench lives at `/workspace/development/frappe-bench/`, which is a bind mount to `frappe_docker/development/` on your Mac — data persists regardless of container lifecycle.

## Daily workflow

### Terminal only

```sh
just up       # start the stack (skip if already running)
just shell    # drop into the frappe container as user `frappe`
```

### With VS Code

```sh
just up       # start the stack first
```

Then in VS Code:

1. Command Palette (`Cmd+Shift+P`) → **Dev Containers: Attach to Running Container**
2. Select **`devcontainer-frappe-1`**
3. In the new window, open folder `/workspace`

> **Always use "Attach to Running Container" — never "Reopen in Dev Container".** The latter manages the container lifecycle itself and will create a new container instead of connecting to yours, which makes it look like your data has disappeared (it hasn't — it's in the old container's volumes).

## First-time VS Code setup (do once, persists in volume)

After attaching for the first time:

1. Install the **Python** extension (publisher: Microsoft) via the Extensions panel
2. Command Palette → **Python: Select Interpreter** → enter path manually:
   `/workspace/development/frappe-bench/env/bin/python`

Both the extension and the interpreter setting are saved inside the container and persist in the `vscode-extensions` named volume. You won't need to repeat this unless you destroy volumes.

The Python interpreter path only exists after `bench init` has been run. If you attach before that, Pylance will show a warning — ignore it until the bench is set up.

## After a reboot

Colima and the containers stop when you shut down or reboot. To resume:

```sh
just colima   # restart Colima
just up       # restart the containers
```

Named volumes (MariaDB data, Redis data, VS Code extensions) are preserved. Your bench at `frappe_docker/development/` is on disk and unaffected.

## Reference

| Command | Description |
|---|---|
| `just colima` | Start Colima VM and set Docker context |
| `just up` | Start devcontainer stack (detached) |
| `just shell` | Enter frappe container as user `frappe` |
| `just dev` | `up` + `shell` in one command |
| `just stop` | Stop containers (preserves volumes) |
| `just restart` | `down` + `up` (preserves volumes) |
| `just logs` | Tail logs from all services |
| `just clean` | **Destructive** — removes containers and all volumes |

## What persists and what doesn't

| Data | Where | Survives restart | Survives `just clean` |
|---|---|---|---|
| MariaDB databases | `mariadb-data` volume | Yes | No |
| Bench + apps | `frappe_docker/development/` (bind mount) | Yes | Yes |
| VS Code extensions | `vscode-extensions` volume | Yes | No |
| VS Code interpreter setting | `vscode-extensions` volume | Yes | No |
