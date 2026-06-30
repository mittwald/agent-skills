# Managed database engines on mStudio

The same freshness discipline as [`app-catalog.md`](app-catalog.md): never hardcode what's available, **query live** during Discovery. This file describes how to ask and how to route.

## The hard rule

mStudio offers **two managed database engines** (at the time of writing):

- **MySQL**
- **Redis**

> **Anything else** — PostgreSQL, MongoDB, MariaDB-specific behavior, ClickHouse, etc. — **must run as a container** in a stack. There is no managed Postgres, no managed Mongo, no managed anything-other-than-MySQL-and-Redis. Don't try to route around this; containerize.

This rule itself is more stable than the version list — adding a new managed engine would require new API endpoints, new MCP tools, and new CLI subcommands, all visible from the surface itself. But the **set of supported versions changes** continually, so for the engines that *are* managed, always live-query.

Verify the rule still holds:

```bash
# CLI — only mysql and redis should appear
mw database --help | sed -n '/TOPICS/,/COMMANDS/p'
# API — only mysql-versions and redis-versions exist; others 404
curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  https://api.mittwald.de/v2/mysql-versions   # expect 200
curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  https://api.mittwald.de/v2/postgres-versions # expect 404
```

## Default: mirror the source engine

For an autonomous migration the **default is to reproduce the source faithfully** — same engine, same major version. Switching engines is a behaviour change whose breakage often surfaces only in production, so it is an **explicit operator decision, never the agent's default**.

- **Source is MariaDB → target is a MariaDB *container*** (matching major, e.g. `mariadb:10.11`). Do **not** import a MariaDB dump into managed MySQL by default. MariaDB and MySQL have diverged — auth plugins, `utf8mb4` collations, system tables, JSON handling, sequences, virtual-column syntax — so schemas usually port but app-level expectations can break after cutover.
- **Source is MySQL → target is MySQL** (managed or container — decided below).
- A MariaDB→MySQL (or any cross-engine) swap is only appropriate when the operator explicitly asks for it and accepts the compatibility risk. Surface it as a question; don't bake it into the plan.

A managed or runtime app can still talk to a container DB by service name (apps and containers share the project network — see "App ↔ container DB networking" below), so **"managed app + container MariaDB" is a fully supported, first-class shape**, not a workaround.

## Live-query primitives

| Operation | MCP | CLI | API |
|---|---|---|---|
| List supported MySQL versions | `mittwald_database_mysql_versions` | `mw database mysql versions` | `GET /v2/mysql-versions` |
| List supported Redis versions | `mittwald_database_redis_versions` | `mw database redis versions -p <projectId>` ⚠ | `GET /v2/redis-versions` |
| Create managed MySQL | `mittwald_database_mysql_create` | `mw database mysql create -p <projectId> …` | `POST /v2/projects/{projectId}/mysql-databases` |
| Create managed Redis | `mittwald_database_redis_create` | `mw database redis create -p <projectId> …` | `POST /v2/projects/{projectId}/redis-databases` |
| MySQL ops (CRUD, users, dump/import, shell, port-forward) | `mittwald_database_mysql_*` | `mw database mysql <subcommand>` | `…/mysql-databases…` |
| Redis ops (CRUD, shell) | `mittwald_database_redis_*` | `mw database redis <subcommand>` | `…/redis-databases…` |

> ⚠ **CLI quirk.** `mw database redis versions` requires `--project-id`; the MySQL equivalent doesn't. The reason is incidental, not semantic — Redis-version listing is project-scoped in the CLI even though the underlying API endpoint isn't. Surface this to the operator if they're confused.

## The `disabled` flag matters

Both `/v2/mysql-versions` and `/v2/redis-versions` return entries with a `disabled` boolean. Example from Redis:

```json
[
  { "id": "redis62", "name": "Redis 6.2", "number": "6.2", "disabled": false },
  { "id": "redis70", "name": "Redis 7.0", "number": "7.0", "disabled": true  },
  { "id": "redis72", "name": "Redis 7.2", "number": "7.2", "disabled": false },
  { "id": "redis86", "name": "Redis 8.6", "number": "8.6", "disabled": false }
]
```

`disabled: true` means **the version is deprecated and not available for new installs**. Filter these out before presenting choices to the operator. If the source happens to run on a `disabled` version (e.g. Redis 7.0), treat it the same as "no compatible version" — operator must upgrade or containerize.

The CLI's tabular output (`mw database mysql versions`) currently does **not** show the `disabled` column. To filter, prefer `-o json` or hit the API directly:

```bash
curl -sS -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  https://api.mittwald.de/v2/redis-versions \
  | jq '.[] | select(.disabled == false) | .number'
```

## Version-compat diff (same shape as the app catalog)

For every DB engine in the source inventory:

1. **Look up the engine.** If it's MySQL or Redis, continue. Else → container, stop.
2. **Query the live version list** via the available surface.
3. **Filter out `disabled` versions.**
4. **Diff the source's version against the remaining list:**
   - Exact match available → use it.
   - Higher version available, source version no longer offered → flag as **upgrade-required**. Either the operator upgrades the source before the dump, or pick a higher target version and accept the in-flight upgrade (test it on a copy first — schema/charset surprises are common, see [`../playbooks/migrate-mysql.md`](../playbooks/migrate-mysql.md)).
   - Source version is older than the lowest non-disabled offering, or only a different major is on offer → **blocker**: operator upgrades source OR containerize this engine even though it's a "managed" type.
5. Record the chosen target version (or "container") and surface it in the Discovery output.

Example:

```
Source: MySQL 5.5
Managed offered (non-disabled): 5.6, 5.7, 8.0, 8.4
Result: upgrade-required from 5.5 to ≥5.6 — propose 5.7 for closest semantics
```

## When **not** to use the managed engine, even if it's offered

- **Source needs config knobs Mittwald doesn't expose.** E.g. a non-default `innodb_buffer_pool_size`, custom `my.cnf` directives, MySQL group replication, Redis cluster mode, Redis persistence tuning beyond defaults. Containerize.
- **Source uses MariaDB-specific features** (sequences, JSON differences, virtual columns with MariaDB syntax). Mittwald-managed MySQL is MySQL, not MariaDB — schemas usually port but app-level expectations may break. Containerize when in doubt.
- **You want a single network namespace for app + DB.** Managed DBs live outside the stack network — the app reaches them via the host returned by `database_mysql_get` / `database_redis_get`, not by a service name (Pitfall #16 doesn't apply to managed DBs). If a single network namespace is important (e.g. for latency or for keeping all credentials inside the stack), containerize.
- **You're already running everything else in the stack** and want operational uniformity (one place to look at logs, one backup procedure, one upgrade procedure). Containerize.

## When the managed engine is the right call

(Assumes the source engine is **MySQL** — for a **MariaDB** source, mirror to a container; see "Default: mirror the source engine".)

- App is a Managed App (e.g. WordPress) where Mittwald is already responsible for the runtime — pair it with a managed DB for consistency and to let Mittwald do the upgrades.
- Source's DB version is well-supported, with no exotic config.
- Operator explicitly wants Mittwald to handle backups, point-in-time recovery, and security patches.
- The DB is a small, well-bounded thing (a Redis cache, a single-app MySQL instance) — managed gives you less surface to operate.

## App ↔ container DB networking

Within a project, **apps and container stacks share the same network**. A managed or runtime app reaches a stack service by its **service name** as hostname (the service's map key in the compose — e.g. `mariadb`), the same way containers reach each other (Pitfall #16). Per the mittwald docs: *"Managed applications and containers are connected to the same network. […] you can access managed applications from your containers and vice versa"* ([containers platform docs](https://developer.mittwald.de/docs/v2/platform/workloads/containers/)).

Consequence: a PHP / Node.js / Python runtime app (or a Managed App) can use a **container database** with `DB_HOST=<service-name>` — no port-forward, no public exposure. This is the recommended shape when mirroring a container-only engine (MariaDB, Postgres, Mongo).

Contrast with **managed** MySQL/Redis, which live *outside* the stack network: reach them via the host from `database_mysql_get` / `database_redis_get`, not a service name (Pitfall #16 does not apply to managed DBs).

## Cross-references

- Provisioning details, including the managed-host vs service-name distinction: [`../playbooks/provision-target.md`](../playbooks/provision-target.md) §7.
- MySQL migration mechanics (dump/restore, dual-target support): [`../playbooks/migrate-mysql.md`](../playbooks/migrate-mysql.md).
- Postgres has **no** managed equivalent; always container: [`../playbooks/migrate-postgres.md`](../playbooks/migrate-postgres.md).
- Surface preference and authentication: [`mittwald-surfaces.md`](mittwald-surfaces.md).

## Pitfalls

- **#18** — Live-query the catalog, never assume. Applies to DB engine versions the same as to apps.
