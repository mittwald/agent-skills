# Mittwald MCP tools — quick reference

The Mittwald MCP server exposes tools under the `mcp__mittwald__mittwald_*` namespace. This sheet groups them by purpose and notes the required parameters and gotchas.

**Universal rule**: pass `projectId` (UUID) explicitly to every call. Don't rely on session context (Pitfall #2).

## Connecting

If `mcp__mittwald__*` tools are absent from the available toolset, the MCP server isn't connected to this Claude session. Operator action: see Mittwald's MCP documentation for setup; this skill cannot install it. Auth (when needed) is exposed as `authenticate` / `complete_authentication`.

## Project / Org

| Tool | Purpose | Notes |
|---|---|---|
| `project_list` | List all projects in scope | First call of any session; resolve short-IDs ↔ UUIDs |
| `project_get` | Project metadata | Required arg: `projectId` |
| `project_create` | Create a new project | Confirm with operator before calling |
| `project_delete` | Delete project (destructive) | **Confirmation gate**; this skill never calls without explicit approval |
| `project_update` | Mutate project metadata | |
| `project_ssh` | Get SSH connection info for the project host | Returns the `user@account@a-XXXXX@ssh.<host>.project.host` form — Pitfall #3 |
| `project_membership_list` / `_get` | Who has access | Read-only; useful for sanity checks |
| `project_invite_*` | Invite flow | Usually operator-driven |
| `org_*` | Organization-level | Similar shape; `org_get`, `org_list`, invite/membership |

## Apps — catalog vs installed

**Two distinct concepts. Don't conflate them (Pitfall #18):**

- **Catalog** = the set of apps Mittwald offers (WordPress, TYPO3, PHP, PHP-Worker, Node.js, …). Read via `app_versions`. Not project-scoped.
- **Installed** = apps actually provisioned in a specific project. Read via `app_list` (projectId required).

See [`app-catalog.md`](app-catalog.md) for the live-query procedure, runtime-app routing matrix, and version-compat diff.

### Catalog tools

| Tool | Purpose | Notes |
|---|---|---|
| `app_versions` | The **catalog**. No args → all apps + versions; `app=<name>` → versions for one app | Not project-scoped. This is what Discovery's catalog self-check calls. |

### Installed-app tools (project-scoped)

| Tool | Purpose | Notes |
|---|---|---|
| `app_list` | List apps **installed in a project** — **not** the catalog. | `projectId` required. |
| `app_get` | Installation metadata | Required arg: `installationId` |
| `app_list_upgrade_candidates` | What can be upgraded for one installation | Required arg: `installationId` |
| `app_upgrade` | Run an upgrade | Destructive in the sense it changes state; confirm |
| `app_copy` | Copy an app installation from another project | Useful for inter-mStudio migrations |
| `app_uninstall` | Remove an installation | Destructive — confirmation gate |
| `app_update` | Configuration change on an installation | |

### MCP gap — no install / create

The MCP server today does **not** expose `app_install` (catalog apps) or `app_create` (runtime apps). To provision a new app installation you must use:

- CLI: `mw app install <name>` (catalog) or `mw app create <runtime>` (PHP / PHP-Worker / Node.js / Python / Static)
- API: `POST` under `/v2/projects/{projectId}/app-installations` — see <https://api.mittwald.de/v2/openapi.json>

Re-check this assumption when MCP's tool list changes. See [`app-catalog.md`](app-catalog.md) and [`mittwald-surfaces.md`](mittwald-surfaces.md).

## Container Stacks (Docker Compose-shaped)

| Tool | Purpose | Notes |
|---|---|---|
| `stack_deploy` | Deploy / update a stack | `state` argument is the compose YAML. Declarative — idempotent re-apply. **Main provisioning tool.** |
| `stack_list` | List stacks in a project | Idempotency check (does a stack already exist?) |
| `stack_ps` | Show container states (running / stopped / error) | After every deploy, before declaring success |
| `stack_delete` | Remove a stack | Destructive — gates required |

## Containers

| Tool | Purpose | Notes |
|---|---|---|
| `container_list` | List containers in the project (across stacks) | |
| `container_start` / `_stop` / `_restart` | Lifecycle | `_stop` makes the container unreachable via Container-SSH (Pitfall #3) |
| `container_logs` | Read recent logs | First debug step on any deploy failure |
| `container_delete` | Destructive | Rare; usually `stack_delete` is the right call |

## Volumes

| Tool | Purpose | Notes |
|---|---|---|
| `volume_list` | List named volumes | |
| `volume_create` | Create a named volume outside of a stack | Most volumes come from `stack_deploy`; only use this for cross-stack shared volumes |

## Domains and DNS

| Tool | Purpose | Notes |
|---|---|---|
| `domain_list` | Domains attached to the project | |
| `domain_get` | Single-domain metadata | |
| `domain_virtualhost_list` | Virtualhosts (hostname → container routing) | Shows the **default `<shortId>.project.space`** alongside custom hostnames (Pitfall #17) |
| `domain_virtualhost_get` | Includes SSL/TLS state, useful post-cutover | |
| `domain_virtualhost_create` | Create a virtualhost | Provisions routing, optionally requests LE cert |
| `domain_virtualhost_delete` | Destructive | |
| `domain_dnszone_list` / `_get` / `_update` | DNS zone management if Mittwald is authoritative | Won't touch zones hosted elsewhere |

## Certificates

| Tool | Purpose | Notes |
|---|---|---|
| `certificate_list` | What certs are issued | |
| `certificate_request` | Request LE or upload custom (Origin Cert) | See Pitfall #10 for Cloudflare interactions |

## Managed Databases

**The rule.** Managed engines are **MySQL and Redis only**. Everything else (Postgres, MongoDB, MariaDB-specific behavior, ClickHouse, …) runs as a container in the stack. See [`database-engines.md`](database-engines.md) for the live self-check, version-diff procedure, and `disabled`-flag handling.

### MySQL

| Tool | Purpose |
|---|---|
| `database_mysql_versions` | What versions are offered. Filter `disabled: true` entries before presenting choices (Pitfall #18). |
| `database_mysql_create` | Provision a managed MySQL DB |
| `database_mysql_list` / `_get` | Inspect |
| `database_mysql_delete` | Destructive |
| `database_mysql_user_create` / `_update` / `_delete` / `_list` / `_get` | User management |

### Redis

| Tool | Purpose |
|---|---|
| `database_redis_versions` | Available versions. Filter `disabled: true` (currently includes Redis 6.0 and 7.0). |
| `database_redis_create` | Provision |
| `database_redis_list` / `_get` | Inspect |

> Postgres / MongoDB / others have **no managed equivalent** — always container in the stack. Don't try to call non-existent `database_postgres_*` tools; they're not there.

## Backups

| Tool | Purpose | Notes |
|---|---|---|
| `backup_create` | One-shot project backup | Take one **at cutover** as rollback insurance |
| `backup_schedule_create` / `_update` / `_delete` / `_list` | Recurring backups | Daily after cutover is a common default |
| `backup_list` / `_get` / `_delete` | Inspect / delete past backups | |

## CronJobs (Mittwald-managed)

| Tool | Purpose |
|---|---|
| `cronjob_create` / `_update` / `_delete` / `_get` / `_list` | Cron definitions |
| `cronjob_execute` | Trigger a cronjob manually |
| `cronjob_execution_list` / `_get` / `_abort` | Inspect / kill running executions |

## Mail

| Tool | Purpose |
|---|---|
| `mail_address_*` | Mailboxes |
| `mail_deliverybox_*` | Delivery boxes |

## SSH and registry

| Tool | Purpose |
|---|---|
| `ssh_user_create` / `_update` / `_delete` / `_list` | Project-host SSH users — required for Project-Host-SSH |
| `registry_create` / `_update` / `_delete` / `_list` | Project image registry — Pitfall #14 |

## User and tokens

| Tool | Purpose |
|---|---|
| `user_get` | Current user info |
| `user_api_token_*` | API tokens for non-MCP automation |
| `user_session_list` / `_get` | Session inspection |
| `user_ssh_key_*` | SSH key registration |

## Context (use sparingly)

| Tool | Purpose |
|---|---|
| `context_get_session` / `_set_session` / `_reset_session` | Session-scoped defaults | **Don't rely on these** — Pitfall #2. Always pass IDs explicitly. |

## Auth

| Tool | Purpose |
|---|---|
| `authenticate` / `complete_authentication` | Interactive auth flow when needed |
