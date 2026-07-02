# Mittwald surfaces — MCP, CLI, API

The skill can drive Mittwald mStudio through **three interchangeable surfaces**. Detect what is available, pick the best fit, and stay consistent within a phase.

## Preference order

1. **MCP** — `mcp__mittwald__mittwald_*` tools. Preferred when present: the agent calls them directly, no shell, no token handling.
2. **CLI** — `mw` (the [mittwald/cli](https://github.com/mittwald/cli)). Use when MCP is unavailable, or when the operator already runs `mw` in their shell, or for operations the CLI does better than MCP (streaming dumps, port-forward, interactive shells).
3. **HTTP API** — [`https://api.mittwald.de/v2/`](https://api.mittwald.de/v2/), spec at [`openapi.json`](https://api.mittwald.de/v2/openapi.json). Use as a last resort, or for operations neither MCP nor CLI expose, or for scripting outside a Claude/Codex session.

If **none** of the three are available, stop and tell the operator. Don't invent calls.

## Detection

### MCP

Check whether any tool with the prefix `mcp__mittwald__mittwald_` is reachable. If not, MCP is not connected to this session — the operator must connect it; this skill cannot install it.

### CLI

```bash
command -v mw && mw --version
```

Install paths: `brew install mw` (after `brew tap mittwald/cli`), `npm i -g @mittwald/cli`, or the `mittwald/cli` Docker image. Docs: <https://developer.mittwald.de/cli>.

Logged-in?

```bash
mw user get -o json    # 401 → not logged in. Equivalent API call: GET /v2/users/self
```

### API

```bash
curl -sS https://api.mittwald.de/v2/openapi.json | head -1
```

Reachability ≠ usability. The skill still needs an `MITTWALD_API_TOKEN` to do anything authenticated.

## Authentication

| Surface | How auth works | Where to get it |
|---|---|---|
| MCP   | Inherits the operator's MCP session. Tools `authenticate` / `complete_authentication` cover interactive login when needed. | Operator's Claude/Codex MCP server config. |
| CLI   | `mw login token` writes a token to `~/.config/mw/token`. Or set `MITTWALD_API_TOKEN` env var (recommended for Docker / non-interactive). The `--token` flag works but is logged in shell history — avoid. | Token at <https://studio.mittwald.de/app/profile/api-tokens>, or have the agent create one via `mcp__mittwald__mittwald_user_api_token_create` (then surface the value once, ask the operator to store it). |
| API   | `Authorization: Bearer <token>` on every request. | Same token source as CLI. |
| **SSH** (Project-Host / Container) | Separate from API auth. Uses SSH public-key auth against the gateway. Two models: **own studio user** (identity = your email; key registered via Studio UI <https://studio.mittwald.de/app/profile/ssh-keys> or via API at `/v2/users/self/ssh-keys` with an `api_write` token) or **per-project ssh-user** (`mw ssh-user create --public-key …` / `mcp__mittwald__mittwald_ssh_user_create`). | See [`ssh-modes.md`](ssh-modes.md) §"Two SSH user models". |

## API token scopes — `403` is almost always a scope issue

API tokens carry **roles** and **fine-grained scopes** that gate what they can do. When the Studio UI offers you a choice at <https://studio.mittwald.de/app/profile/api-tokens>, the two main roles are:

- **`api_read`** — read-only across resources the operator has access to
- **`api_write`** — read + write

Under the hood, ~45 fine-grained scopes exist in the shape `<resource>:<action>` (e.g. `app:read`, `app:write`, `app:delete`, `backup:read`, `backup:write`, `backup:delete`, `domain:read`, …). List them via `GET /v2/scopes`.

**This skill needs `api_write`.** Provisioning, backup creation, stack deploys, SSH-key registration, and other write actions all require it. A `api_read` token will produce confusing `403`s on operations that *look* like they should work.

### Diagnosing a `403`

```bash
# 1. confirm token is set
[ -n "$MITTWALD_API_TOKEN" ] && echo "token present (len=${#MITTWALD_API_TOKEN})"

# 2. inspect this token's roles
curl -sS -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  https://api.mittwald.de/v2/users/self/api-tokens \
  | jq '.[] | {description, roles}'
# look for the entry matching your token's description, check roles[]
```

If the token has `api_read` only but the failing call needs to mutate state, **re-issue the token with `api_write`** before treating the `403` as a fundamental limitation. See Pitfall #21.

## When to use which (operationally)

| Situation | Preferred surface | Why |
|---|---|---|
| Routine reads / writes during a phase | MCP | Lowest friction, no shell roundtrip |
| Operator already runs `mw` in their shell | CLI | Keep them in their flow; agent narrates instead of acting |
| MySQL dump / import streaming | CLI (`mw database mysql dump` / `... import`) | MCP doesn't expose data-plane stream; CLI does it natively |
| Port-forward into a managed DB for local tooling | CLI (`mw database mysql port-forward`) | Same reason |
| Interactive shell into a DB | CLI (`mw database mysql shell` / `... redis shell`) | Same reason |
| Bulk / scripted operations outside this session | API | Token-driven, reproducible, no client dependency |
| Compose-file deploy via stdin | CLI (`mw stack deploy -c -`) | Convenient for piped templates |
| Operations where only one surface supports it | That one | See Rosetta gaps below |

## Universal rules (apply to every surface)

- **Pass `projectId` (UUID) explicitly** to every call (MCP `projectId`, CLI `-p / --project-id`, API path/query param). Both MCP session context and the CLI's `mw context set` are stale-prone — see Pitfall #2.
- **Resolve short-IDs to UUIDs first.** All three surfaces accept short-IDs in many places, but Pitfall #1 still applies — classify before passing.
- **Confirmation gates are surface-independent.** A destructive action needs explicit operator approval whether you call it via MCP, `mw stack delete`, or `DELETE /v2/stacks/{stackId}`.

## CLI usage patterns the skill leans on

- `-o json` (or `yaml`/`csv`) for machine-readable output **on read/list commands** — parse this, don't grep the human `txt` format. **Mutation commands don't have `-o json`** (they use `-q`, next bullet), and a few commands reuse `-o` for something else entirely — `mw database mysql dump -o <file>` is the **output file**, not a format. Route the flag by command kind; don't assume `-o json` works everywhere (Pitfall #27).
- `-q / --quiet` for mutation/action commands (`mw app install`, `mw app exec`, `mw database mysql import`) — "suppress process output, show a machine-readable summary." This is where you read created-resource IDs. Don't expect `-o json` on these.
- **Flag sets drift across CLI versions.** A command that offered `-o json` in one release may not in another. When a script must survive that drift, probe the installed version's help before committing to a parse path: `mw <cmd> --help 2>&1 | grep -qE '^\s*-o,? *--output'` before parsing JSON, else fall back to `-q` (Pitfall #27).
- `-w / --wait` + `--wait-timeout=<dur>` to block until a resource is ready (DB, stack rollout). The skill defaults to short timeouts and reports progress.
- `MITTWALD_API_TOKEN` env over `--token <value>` flag. The flag is logged in shell history.
- `MITTWALD_SSH_IDENTITY_FILE` / `MITTWALD_SSH_USER` (or `--ssh-identity-file` / `--ssh-user`) pick the key and user for the SSH-tunnelling commands — e.g. `mw app exec` and `mw database mysql import`/`dump` (verified on `mw 1.19.0`). Handy in headless/CI runs where the key isn't the default `~/.ssh/id_*`, instead of editing `~/.ssh/config`. See [`ssh-modes.md`](ssh-modes.md) § "Source-side SSH access".
- `mw context set --project-id=<id>` — **avoid in agent-run scripts.** It hides which project a command affects and makes resume-after-crash ambiguous. Always pass `-p` explicitly (Pitfall #2).
- **Positional vs flag inconsistency.** Most `mw` subcommands take the project as `-p / --project-id`, but a few accept it as a **positional argument** and reject `-p`. Known: `mw project ssh <projectId>`, `mw app versions [APP]`. When in doubt, `mw <cmd> --help` is authoritative.

## Rosetta — operations the skill uses

Identifier convention below: `{projectId}` etc. are UUIDs. CLI accepts short-IDs in many places; API does not.

### Project / org

| Operation | MCP | CLI | API |
|---|---|---|---|
| List projects | `project_list` | `mw project list -o json` | `GET /v2/projects` |
| Get project | `project_get` | `mw project get {projectId} -o json` ⚠ project is a **positional** arg, not `-p` | `GET /v2/projects/{projectId}` |
| Create project | `project_create` | `mw project create ...` | `POST /v2/servers/{serverId}/projects` |
| Delete project (destructive) | `project_delete` | `mw project delete {projectId} -f` | `DELETE /v2/projects/{projectId}` |
| Assemble SSH connection info | `project_ssh` (returns ready-to-use ssh command) | `mw project ssh <projectId>` ⚠ takes the project as a **positional** arg, not `-p` — opens an interactive shell directly | composed from `clusterId` + `clusterDomain` + `shortId` on the project object, plus an app or container shortId. No single endpoint; see [`ssh-modes.md`](ssh-modes.md) §"Assembling the SSH command from API fields". |
| Org list / get | `org_list` / `org_get` | `mw org list` / `mw org get {orgId}` | `GET /v2/organizations[/{orgId}]` |

### Container stacks

| Operation | MCP | CLI | API |
|---|---|---|---|
| Deploy / update stack | `stack_deploy` | `mw stack deploy -c docker-compose.yml` (or `-c -` for stdin) | `PUT /v2/projects/{projectId}/stacks/{stackId}` (declarative) |
| List stacks | `stack_list` | `mw stack list -o json` | `GET /v2/projects/{projectId}/stacks` |
| Show containers in stack | `stack_ps` | `mw stack ps -s {stackId} -o json` | `GET /v2/projects/{projectId}/stacks/{stackId}/services` |
| Delete stack (destructive) | `stack_delete` | `mw stack delete {stackId} -f` (`-v` includes volumes) | `DELETE /v2/projects/{projectId}/stacks/{stackId}` |

### Containers

| Operation | MCP | CLI | API |
|---|---|---|---|
| List containers in project | `container_list` | `mw container list -o json` | Not a top-level project endpoint — containers are nested: `GET /v2/projects/{projectId}/stacks` → `[].services[]` (each has its own `shortId`/`id`). |
| Start / stop / restart / recreate / pull | `container_start` / `_stop` / `_restart` | `mw container start/stop/restart {containerId}` | `POST /v2/stacks/{stackId}/services/{serviceId}/actions/{start\|stop\|restart\|recreate\|pull}` |
| Logs | `container_logs` | `mw container logs {containerId}` | `GET /v2/stacks/{stackId}/services/{serviceId}/logs` |

### Managed databases — engines

Managed engines on mStudio: **MySQL and Redis only**. Everything else → container. See [`database-engines.md`](database-engines.md) for the live self-check and `disabled`-flag handling.

### MySQL (managed)

| Operation | MCP | CLI | API |
|---|---|---|---|
| Versions (filter `disabled: true`) | `database_mysql_versions` | `mw database mysql versions -o json` | `GET /v2/mysql-versions` |
| Create DB | `database_mysql_create` | `mw database mysql create ...` | `POST /v2/projects/{projectId}/mysql-databases` |
| Get / list DBs | `database_mysql_get` / `_list` | `mw database mysql get/list` | `GET /v2/projects/{projectId}/mysql-databases[/{id}]` |
| **Dump** (streaming) | — (use CLI) | `mw database mysql dump {dbId} -o dump.sql` (`-o -` for stdout; `--gzip`) ⚠ here `-o` is the **output file**, *not* `-o json` | — (use CLI) |
| **Import** (streaming) | — (use CLI) | `mw database mysql import {dbId} -i dump.sql` (`-i -` for stdin; `--gzip` for gzipped input) ⚠ `-p` here is `--mysql-password`, **not** project-id | — (use CLI) |
| **Port-forward** | — (use CLI) | `mw database mysql port-forward {dbId} --port 3307` | — (use CLI) |
| **Interactive shell** | — (use CLI) | `mw database mysql shell {dbId}` | — (use CLI) |
| User CRUD | `database_mysql_user_*` | `mw database mysql user create/list/get/update/delete` | `…/users…` under the DB path |

> **`--temporary-user` on dump/import — convenient, verified working (1.18.0).** Both `mw database mysql dump` and `import` accept `--temporary-user` to spin up a throwaway MySQL user for the operation and drop it afterwards — no need to know the DB user's password. **Verified end-to-end on `mw 1.18.0`** (import + dump both create and remove the temp user cleanly). One older migration reported the import 404ing while fetching the temp user back; that did **not reproduce** on 1.18.0, so treat it as version-specific. If you hit it on an older CLI, **upgrade `mw`** first, or fall back to the existing app/DB user (`mw database mysql user list --database-id <id>` for the name, password via `-p`/`MYSQL_PWD`). See [`../playbooks/migrate-mysql.md`](../playbooks/migrate-mysql.md) §4a.

### Redis (managed)

| Operation | MCP | CLI | API |
|---|---|---|---|
| Versions (filter `disabled: true`; CLI requires `-p`) | `database_redis_versions` | `mw database redis versions -p {projectId} -o json` ⚠ | `GET /v2/redis-versions` |
| Create / get / list | `database_redis_create` / `_get` / `_list` | `mw database redis create/get/list` | `…/redis-databases…` |
| Shell | — (use CLI) | `mw database redis shell {dbId}` | — (use CLI) |

> ⚠ Unlike `mw database mysql versions`, the Redis equivalent requires `--project-id`. Underlying API endpoint isn't project-scoped, but the CLI is. See [`database-engines.md`](database-engines.md).

### Domains, virtualhosts, DNS

| Operation | MCP | CLI | API |
|---|---|---|---|
| List / get domain | `domain_list` / `_get` | `mw domain list -o json` / `mw domain get {id}` | `GET /v2/projects/{projectId}/domains[/{id}]` |
| List virtualhosts | `domain_virtualhost_list` | `mw domain virtualhost list -o json` | `GET /v2/projects/{projectId}/ingresses` |
| Create / delete virtualhost | `domain_virtualhost_create` / `_delete` | `mw domain virtualhost create/delete` | `POST` / `DELETE /v2/projects/{projectId}/ingresses[/{id}]` |
| Update virtualhost **paths** (re-route) | — | — (no CLI command yet; delete+recreate, or use API) | `PATCH /v2/ingresses/{ingressId}/paths` — **resource-scoped**, not under `…/projects/{id}/…` |
| Get DNS zone | `domain_dnszone_get` / `_list` | `mw domain dns get/list` | `GET /v2/projects/{projectId}/dns-zones[/{id}]` |
| Update DNS zone | `domain_dnszone_update` | `mw domain dns update {zoneId}` | `PUT /v2/projects/{projectId}/dns-zones/{id}/records` |

### Certificates

| Operation | MCP | CLI | API |
|---|---|---|---|
| List | `certificate_list` | (see `mw domain` subcommands) | `GET /v2/projects/{projectId}/certificates` |
| Request / upload | `certificate_request` | (operator-side; CLI coverage limited) | `POST /v2/projects/{projectId}/certificates` |

### Backups

| Operation | MCP | CLI | API |
|---|---|---|---|
| One-shot backup | `backup_create` | `mw backup create --expires 30d` | `POST /v2/projects/{projectId}/backups` |
| List / get / delete | `backup_list` / `_get` / `_delete` | `mw backup list/get/delete` | `GET` / `DELETE /v2/projects/{projectId}/backups[/{id}]` |
| Download | — | `mw backup download {id}` | dedicated endpoint via signed URL |
| Schedules | `backup_schedule_*` | `mw backup schedule list` (+ create/update/delete) | `…/backup-schedules…` |

> ⚠ The `mw project backup …` / `mw project backupschedule …` forms are **deprecated** — the CLI now nests these under `mw backup …` / `mw backup schedule …`.

### Registry, SSH users, volumes

| Operation | MCP | CLI | API |
|---|---|---|---|
| Project image registry | `registry_create` / `_update` / `_delete` / `_list` | `mw registry create/list/...` | `…/container-registries…` |
| SSH users (project host) | `ssh_user_create` / `_update` / `_delete` / `_list` | `mw ssh-user create/list/...` | `…/ssh-users…` |
| Named volumes | `volume_list` / `_create` | `mw volume list/...` | `…/volumes…` |

### Apps — catalog (read-only)

See [`app-catalog.md`](app-catalog.md) for the full procedure (live query + routing + version diff). Distinct from "installed apps" rows below — don't conflate (Pitfall #18).

| Operation | MCP | CLI | API |
|---|---|---|---|
| List the whole catalog | `app_versions` (no `app` arg) | `mw app versions` | `GET /v2/apps` |
| List versions for one app | `app_versions` (`app="wordpress"`) | `mw app versions <name>` | `GET /v2/apps/{appId}/versions` |
| Inspect version (userInputs, recommended flag) | — (use CLI / API) | `mw app version-info <versionId>` | `GET /v2/app-versions/{versionId}` |

### Apps — installed in a project

| Operation | MCP | CLI | API |
|---|---|---|---|
| List installed apps | `app_list` (projectId required) | `mw app list -p {projectId}` | `GET /v2/projects/{projectId}/app-installations` |
| Get installation | `app_get` (installationId) | `mw app get <installationId>` | `GET /v2/app-installations/{installationId}` |
| Install catalog app (Managed App) | — (MCP gap) | `mw app install <name> -p {projectId}` | `POST /v2/projects/{projectId}/app-installations` |
| Create runtime app (PHP / PHP-Worker / Node / Python / Static) | — (MCP gap) | `mw app create <runtime> -p {projectId}` | `POST /v2/projects/{projectId}/app-installations` |
| Upgrade | `app_upgrade` | `mw app upgrade` | `PATCH …/app-installations/{id}` |
| List upgrade candidates | `app_list_upgrade_candidates` | `mw app list-upgrade-candidates` | `GET …/upgrade-candidates` |
| Copy installation between projects | `app_copy` | `mw app copy` | (see OpenAPI) |
| Uninstall (destructive) | `app_uninstall` | `mw app uninstall <id> -f` | `DELETE …/app-installations/{id}` |

> **MCP gap.** No `app_install` / `app_create` tools today. Provisioning a new installation must go through CLI or API. Re-check when MCP's tool list changes.

### User & tokens

| Operation | MCP | CLI | API |
|---|---|---|---|
| Current user | `user_get` | `mw user get -o json` | `GET /v2/users/self` |
| API tokens | `user_api_token_*` | (managed in mStudio UI; CLI focuses on consuming tokens) | `…/users/self/tokens…` |

**Generate an API token**: <https://studio.mittwald.de/app/profile/api-tokens>. Same token works for CLI (`MITTWALD_API_TOKEN` env or `mw login token`) and API (`Authorization: Bearer …`).

> **Coverage caveat.** The CLI command tree evolves; treat the `mw <topic> --help` output (or `mw help <topic>`) as authoritative. The API spec is authoritative for the API. The MCP tool list at session start is authoritative for MCP. If a row above looks wrong, trust the surface, fix the row.

## External resources

- **Developer portal**: <https://developer.mittwald.de/> — SDKs (Go / TypeScript / PHP), additional tooling, ongoing-work notes. Consult before reaching for a raw API call if a higher-level client already exists.
- **OpenAPI spec**: <https://api.mittwald.de/v2/openapi.json> — generate clients, look up exact request/response shapes, find endpoints not yet wrapped by MCP or CLI.
- **CLI docs**: <https://developer.mittwald.de/cli>, source at <https://github.com/mittwald/cli>.
- **MCP cheatsheet (this repo)**: [`mittwald-mcp-tools.md`](mittwald-mcp-tools.md) — categorized MCP tool list with required params and gotchas.

## Pitfalls that span surfaces

- **#1 ID-class confusion** — UUID vs short-ID vs name. All three surfaces blur this in different ways.
- **#2 Stale default context** — MCP `context_get_session` *and* `mw context set --project-id` both create silent defaults. Always pass IDs explicitly.
- **#18 Hardcoded catalog / app_list vs app_versions** — the catalog is `app_versions` (no projectId); `app_list` is *installed apps* in a project. Don't conflate. See [`app-catalog.md`](app-catalog.md).
