# Playbook: Plan and provision the target

**Goal:** decide the target shape on mStudio, then create the project, stack, virtualhosts and domains so the migration phase has somewhere to write.

Entry condition: Discovery output approved by the operator.

## 1. Pick the target app type

The decision was already made in Discovery's catalog self-check ([`discover-source.md`](discover-source.md) §7, with the full procedure in [`../references/app-catalog.md`](../references/app-catalog.md)). At this point the operator has approved one of:

- **Managed App** — a catalog entry like WordPress, TYPO3, Joomla, Nextcloud, Shopware, etc. Mittwald owns the runtime and update path.
- **Runtime app** — `php`, `php-worker`, `node`, `python`, or `static`. Mittwald supplies the runtime; you ship the code. For PHP applications with background workers, the conventional shape is **one PHP app + N PHP-Worker apps** in the same project — do not bake workers into the web app's container.
- **Container Stack** — Compose-shaped YAML, deployed as a stack of services. You own everything. The escape hatch for workloads that don't fit a Managed or runtime app.

> Don't re-litigate this decision here. If the decision feels wrong, return to Discovery §7 — that's where the catalog query happens, and the catalog might have moved since you last looked.

The remaining sections branch by chosen type:

- **Managed App** → §2 + §3a
- **Runtime app (PHP / PHP-Worker / Node.js / Python / Static)** → §2 + §3b
- **Container Stack** → §2 + §4 onward (compose layout, deploy, virtualhost)

## 2. Project: reuse or create

```text
List projects:        mcp__mittwald__mittwald_project_list
Get a project:        mcp__mittwald__mittwald_project_get  (always pass projectId explicitly — Pitfall #2)
Create a project:     mcp__mittwald__mittwald_project_create
```

Ask the operator: "Use existing project `<shortId>` or create new?" Always pass the long `projectId` (UUID) downstream, never the short ID (Pitfall #1).

## 3a. Provision a Managed App (catalog) or runtime app

> Only for **Managed App** and **runtime app** target shapes. For Container Stack, skip to §3 / §4.

### MCP gap

The Mittwald MCP server today does **not** expose `app_install` or `app_create` tools — only `app_list` (installed), `app_get`, `app_versions` (catalog), `app_upgrade`, `app_copy`, etc. To actually create a new installation you must use the CLI or API. See [`../references/app-catalog.md`](../references/app-catalog.md) for the up-to-date MCP-coverage caveat.

### CLI path

```bash
# Managed App (catalog)
mw app install <name> -p <projectId> [--version <ver>] [<app-specific flags>]
# examples:
mw app install wordpress -p <projectId> --version 6.6.2
mw app install typo3     -p <projectId>

# Runtime app (self-managed)
mw app create <runtime> -p <projectId> [<runtime-specific flags>]
# examples:
mw app create php        -p <projectId>
mw app create node       -p <projectId>
mw app create php-worker -p <projectId>   # one per worker class; pair with the PHP app above
mw app create static     -p <projectId>
```

Always run `mw app install <name> --help` / `mw app create <runtime> --help` first — the per-app flag set evolves. Confirm version flags against the live `mw app versions <name>` list before committing (Pitfall #18).

### API path

Equivalent endpoints exist under `/v2/projects/{projectId}/app-installations` — consult <https://api.mittwald.de/v2/openapi.json> for the exact request shape and required `appVersionId`.

### After install / create — WAIT for readiness first

App provisioning is **asynchronous**. Right after `app create` / `app install` the installation sits in `phase: pending` → `installing` for seconds-to-minutes before it's usable. SSH, filesystem access, and any migration step **fail confusingly** if you start them too early (Pitfall #25).

**Two ways to wait:**

```bash
# CLI — preferred: block on the create/install call itself
mw app install wordpress -p <projectId> -w --wait-timeout 600s
mw app create php        -p <projectId> -w --wait-timeout 600s
```

```text
# MCP / API — no install/create wait flag (and MCP can't install at all).
# Poll app_get until phase == "ready":
mcp__mittwald__mittwald_app_list      projectId=<uuid>     # capture installationId
mcp__mittwald__mittwald_app_get       installationId=<id>  # read the `phase` field
```

The `phase` field is the readiness indicator (enum: `pending`, `installing`, `upgrading`, `ready`, `disabled`, `reconfiguring`). **Treat only `phase == "ready"` as usable.** Narrate the wait to the operator — don't silently block.

The installation produces:

- `installationId` (UUID) — used by `app_get`, `app_upgrade`, `app_uninstall`, `app_copy`, `app_list_upgrade_candidates`.
- `shortId` / `hostname` — the `a-XXXXX` token used as the Project-Host-SSH routing fragment (below).
- A default URL on `<shortId>.project.space` for smoke-testing (Pitfall #17), same as with stacks.
- `installationPath` — where the app's files live, **relative to the project home** (`/home/<p-shortId>/`). Default web apps install at `/html`; others get a named subdirectory (e.g. `/csv-to-invoice-uyqyb`). The document root is `installationPath` + `customDocumentRoot`.

> **App files live under the project home, NOT under `/files/` (Pitfall #4).** An app's content is at `/home/<p-shortId>/<installationPath>` — `/home/<p-shortId>/html` for a default web app. `/files/` is the bind-mount convention for **container stacks**, a different thing. Don't look for a migrated app's files under `/files/`. Read the exact path from the project's `directories.Web` or the app's `installationPath`.

### Establish SSH access to the new app

Once `phase == "ready"`, you'll need SSH to reach the app's files (under `/home/<p-shortId>/<installationPath>`, default `/html`) for file migration, php.ini overrides, etc. Project-Host-SSH requires an SSH credential — establish it now so the Migrate phase isn't blocked:

- **Own studio user** (default): if the operator's public key is already registered (Studio UI or `POST /v2/users/self/ssh-keys`, see [`../references/ssh-modes.md`](../references/ssh-modes.md) and the README), no per-project setup is needed. The SSH identity is their email.
- **Per-project ssh-user** (CI / service account): create one scoped to this project:

  ```text
  mcp__mittwald__mittwald_ssh_user_create   projectId=<uuid>  publicKey=<ssh-…>  description="migration"
  # CLI: mw ssh-user create -p <projectId> --public-key "$(cat ~/.ssh/id_ed25519.pub)" --description "migration"
  mcp__mittwald__mittwald_ssh_user_list     projectId=<uuid>  # confirm + capture userName
  ```

Then assemble the SSH command: `<identity>@<a-XXXXX>@ssh.<cluster>.project.host`, where `<a-XXXXX>` is the app installation's `shortId`/`hostname`. Full composition (cluster fragment, identity rules) in [`../references/ssh-modes.md`](../references/ssh-modes.md) §"Assembling the SSH command from API fields". A freshly-issued ssh-user is itself near-instant, but it still only reaches the app once the app is `phase == "ready"` (Pitfall #25).

> **TYPO3 Composer note (Pitfall #22).** Composer-based TYPO3 installs have their webroot at `<install>/public/`, not at `<install>/`. When provisioning as a PHP runtime app or in a Container Stack, the document root must include `/public`. Symlink-based TYPO3 doesn't have this requirement — the layouts differ. Identify which one Discovery found in [`../references/cms-quirks.md`](../references/cms-quirks.md).

### PHP runtime config (php.ini)

For any PHP-based app (Managed Apps like WordPress/TYPO3/Shopware, PHP runtime apps, and Container-Stack PHP services), php.ini settings are overridden in **one of two places** — pick by scope. **Don't edit the runtime's main `php.ini` directly; use one of these:**

**A — a dedicated drop-in under `~/.config/php/php.d/`** (project-wide). Add your own `.ini` file; one concern per file is fine:

```text
/home/<p-shortId>/.config/php/php.d/zz-migration.ini
```

Reachable via Project-Host-SSH (see [`../references/ssh-modes.md`](../references/ssh-modes.md)). Use this when the setting should apply across the project, or for `PHP_INI_SYSTEM` directives (e.g. `extension=…`) that `.user.ini` can't change.

**B — a `.user.ini` in the app directory** (per-app, travels with the code):

```text
<app-dir>/.user.ini
```

```ini
memory_limit = 512M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
date.timezone = "Europe/Berlin"
```

Use this when the settings should live with the application code (committed, included in deploy artefacts) so they're reproducible without manual SSH. Caveats: `.user.ini` only affects `PHP_INI_PERDIR` / `PHP_INI_USER` directives — `extension=…`, `disable_functions` and other `PHP_INI_SYSTEM` directives must go in the `php.d/` drop-in (A). PHP caches `.user.ini` for `user_ini.cache_ttl` seconds (default 300), so changes aren't instant.

> **Don't confuse `.user.ini` (PHP) with `user.ini` (Wordfence).** No leading dot, different purpose — Wordfence's WAF uses `user.ini` for its own bootstrap and that file holds hardcoded paths that break on Mittwald (Pitfall #23). Separate concerns.

Discovery (`discover-source.md` §4) captured the source's settings — replicate the ones that actually matter, regardless of which place you pick:

- `memory_limit` — most common breakage when too low (large GD operations, big queries, plugin bloat)
- `upload_max_filesize` and `post_max_size` — both need bumping for large media uploads; `post_max_size` must be ≥ `upload_max_filesize`
- `max_execution_time` — long-running CMS operations (image processing, search re-index, plugin updates)
- `date.timezone` — silent log-timestamp drift if missing
- `opcache.*` — performance-critical; defaults usually fine, but if source had specific tuning, replicate it
- Any custom extensions the app loads (`extension=…`) — **`php.d/` drop-in only** (A). Confirm the extension ships in Mittwald's PHP runtime; if not, the app may need a different runtime version or a Container Stack instead.

The `php.d/` drop-in (A) applies on the next request (or worker restart for PHP-Worker apps); the `.user.ini` (B) applies after the `user_ini.cache_ttl` window expires.

### PHP + workers shape

When the source has Supervisor-style background workers tied to a PHP application, the recommended layout is:

- One **PHP runtime app** for the web request path.
- One **PHP-Worker app** per worker class (queue worker, scheduler runner, etc.) — `mw app create php-worker` with the worker's command line. Each PHP-Worker app gets its own lifecycle, restart, and logs.
- They share the project, not the installation. Shared state (DB, Redis, and the app files under the project home `/home/<p-shortId>/`) is reached via the project, not via app-internal IPC.

This is **not the same** as packing workers into one container in a stack — runtime apps are the native model and worth using when the source workload fits.

### Skipping the stack path

If you provisioned via Managed App or runtime app, **most of the rest of this playbook (compose layout, stack_deploy) doesn't apply** — Mittwald provisioned the runtime for you. Jump to §6 for virtualhosts / domains, then to the Migrate phase.

## 3. Container layout

Design a Compose-shaped stack. Conventions used by these playbooks:

- **One service per role**: `app`, `postgresql`, `redis`, `worker`, etc.
- **Service names are the in-stack hostnames** (Pitfall #16). `WP_DB_HOST=postgresql` works — no IPs.
- **Bind-mounts under `/files/<appname>/<purpose>/`** for anything the operator must reach from Project-Host-SSH (database dumps in transit, uploads, app assets). Bind-mounts are writable from Project-Host-SSH; named volumes are not (Pitfall #4). **If the container writes to the bind-mount, pre-create the directory and `chmod 777` (or `chown` to the known runtime uid) via Project-Host-SSH BEFORE `stack deploy`** — rootless containers can't fix ownership on first start (Pitfall #20).
- **Named volumes for DB data directories** (`pgdata:/var/lib/postgresql/data`). The DB only reads/writes its own datadir; the operator doesn't need to poke at it from outside.
- **Exception — stateful containers that need offline pre-load.** Solr indices, custom blobstores, on-disk segment formats etc. that must be populated *before* the container's first start need a **bind-mount** (`/files/<app>/solr-data:/var/solr/data`), not a Named Volume. The operator can't reach Named Volumes from Project-Host-SSH while the container is stopped (Pitfalls #3 + #4). Full workaround: [`../references/stateful-container-restore.md`](../references/stateful-container-restore.md), Pitfall #19. Decide this **now**, at compose-layout time — switching from named volume to bind-mount later requires re-deploying and re-loading data.
- **`restart: unless-stopped`** on every service.
- **No `ports:` exposure** unless the service is genuinely external. The first virtualhost terminates TLS and proxies to the app service.

Reference: see `references/compose-templates/` for ready snippets.

## 4. Resource sizing (rule of thumb)

- DB container: 1 vCPU / 1 GB RAM per ~5 GB of DB, +1 GB headroom. Bump if Discovery showed heavy joins / vacuum pressure.
- App container: match what the source actually used. Don't pad "just in case".
- Total bind-mount storage: 2× of measured `du` for transit headroom during migration. Shrink after cutover if needed.

Surface these as a small table to the operator before deploying — they own the cost.

## 5. Deploy the stack

```text
mcp__mittwald__mittwald_stack_deploy
  projectId: <uuid>
  state: <compose YAML>
```

The call is **declarative** — it applies the YAML as desired state. Idempotent (Pitfall: re-deploys are safe to retry).

After deploy:

```text
mcp__mittwald__mittwald_stack_list      # confirm stack present, get stackId
mcp__mittwald__mittwald_stack_ps        # confirm all services in 'running' state
mcp__mittwald__mittwald_container_logs  # spot-check each service
```

If a service is restart-looping, **read the logs before touching anything else**. Common causes: missing env var, wrong image tag, volume permission, DB not ready yet.

## 6. Virtualhosts and the default domain

Every stack needs at least one virtualhost so it gets the **default `<shortId>.project.space` address** (Pitfall #17) — that's how you smoke-test before DNS cutover.

```text
mcp__mittwald__mittwald_domain_virtualhost_create
  projectId: <uuid>
  hostname: <intended-public-hostname>           # the real domain
  paths:
    "/": { container: { name: "app", port: 3000 } }
```

You don't need DNS to point at Mittwald yet. The virtualhost is created in a "DNS-pending" state; the **default `<shortId>.project.space` URL works immediately** and proxies to the same container/path config. That's your test surface.

For the real domain:

```text
mcp__mittwald__mittwald_domain_virtualhost_list    # check current state + LE status
mcp__mittwald__mittwald_certificate_list           # see what certs exist
```

Don't request a Let's Encrypt cert for a hostname that doesn't yet resolve to Mittwald — it'll fail HTTP-01 (Pitfall #10). Wait until cutover, or hand-place a Cloudflare Origin Cert via `certificate_request` if applicable.

## 7. Managed databases vs containerized

The decision was already made in Discovery's DB-engines self-check ([`discover-source.md`](discover-source.md) §7b, with the full procedure in [`../references/database-engines.md`](../references/database-engines.md)). Recap and act:

> **Managed engines on mStudio are MySQL and Redis. Everything else (Postgres, MongoDB, …) runs as a container in the stack.** Re-verify the rule via `mw database --help` if you're unsure.

### Managed MySQL

```text
mcp__mittwald__mittwald_database_mysql_versions     # confirm chosen version is offered and not disabled
mcp__mittwald__mittwald_database_mysql_create
mcp__mittwald__mittwald_database_mysql_user_create
mcp__mittwald__mittwald_database_mysql_get          # capture host + port for app env
```

Managed MySQL is **separate from the stack**. The app container reaches it via the host returned by `database_mysql_get`, not by a service name — Pitfall #16 (service-name-as-hostname) **does not apply** to managed DBs. Set `DB_HOST` from the returned host explicitly.

### Managed Redis

```text
mcp__mittwald__mittwald_database_redis_versions     # confirm chosen version is offered and not disabled
mcp__mittwald__mittwald_database_redis_create
mcp__mittwald__mittwald_database_redis_get          # capture host + port for app env
```

Same network-namespace caveat as MySQL: separate from the stack, app reaches it via the returned host. CLI quirk: `mw database redis versions` requires `-p <projectId>` even though it's the same global version list.

### Container DBs (everything else)

Postgres, MongoDB, MariaDB-specific behavior, ClickHouse, etc. — declare a service in the compose YAML the same way as the app. Name it after the engine (`postgresql`, `mongo`, `mariadb`); the service name becomes the in-stack hostname (Pitfall #16). Mount data on a named volume (`pgdata:/var/lib/postgresql/data`), not a bind-mount (Pitfall #4). Templates: [`../references/compose-templates/postgres-app.yml`](../references/compose-templates/postgres-app.yml), [`../references/compose-templates/mysql-app.yml`](../references/compose-templates/mysql-app.yml).

> **Don't try to route a non-MySQL/non-Redis engine through the managed path.** It doesn't exist; the call will fail (404 / "not found"). Containerize.

## 8. Image availability check

Before deploy, confirm every image referenced in the compose YAML is reachable:

- `library/*`, `bitnami/*`, official Docker Hub — fine.
- Anything from `ghcr.io`, `registry.gitlab.com`, internal registries — **the Mittwald runtime must be able to pull it**. Push to the Mittwald Project Registry first if it's private (Pitfall #14):

  ```text
  mcp__mittwald__mittwald_registry_create     # if not yet present
  mcp__mittwald__mittwald_registry_list
  ```

  Image path will be `<project-shortId>.project.space/<image>:<tag>`.

## 9. Confirmation gate before stack_deploy

Summarize for the operator:

```
About to deploy stack <name> into project <shortId> (<uuid>):
  - services: app, postgresql, redis
  - bind-mounts: /files/<app>/postgres-dumps, /files/<app>/uploads
  - named volumes: pgdata
  - virtualhost: <hostname> (default: <shortId>.project.space)
  - images: <list, all reachable: yes/no>
Estimated monthly cost impact: <Mittwald's plan calculator if available>
Rollback: stack_delete + project_delete (no source data touched yet).
```

Ask `AskUserQuestion`: approve / change shape / cancel.

## 10. End of phase

Outputs to record for later phases:

- `projectId` (UUID)
- `stackId` (UUID)
- service shortIds (for Container-SSH later — Pitfall #3)
- bind-mount host paths
- default `<shortId>.project.space` hostname
- which DB target was chosen (container Postgres / container MySQL / managed MySQL)

Update the TodoWrite list: Provision → completed, Migrate → in_progress.

## Pitfalls referenced in this phase

- #1 ID hygiene
- #2 Pass `projectId` explicitly
- #3 SSH modes — record service shortIds now, you'll need them in Migrate
- #4 Where data lives — apps under `/home/<p>/<installationPath>` (`/html`); stack bind-mounts under `/files/`; named volumes container-only
- #10 Cloudflare and LE
- #14 Private images / Project Registry
- #16 Service name = hostname inside the stack
- #17 Default `<shortId>.project.space` is your smoke-test surface
- #18 Catalog and per-app version list are queried live; MCP can't currently install — fall back to CLI / API
- #19 Stateful containers needing offline pre-load require bind-mount + dummy app — decide at compose-layout time
- #20 Rootless container: pre-create + chmod the bind-mount directory before stack_deploy
- #22 TYPO3 Composer installation: webroot must be <install>/public — decide at virtualhost-config time
- #25 App provisioning is async — wait for phase==ready before SSH/migration
