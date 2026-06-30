# Playbook: Discover the source

**Goal:** produce a written inventory the operator can confirm before any provisioning. Source type is unknown at this point — adapt the commands.

## 0a. Pre-flight: confirm surface + token scope

Before any catalog or DB-engines query, confirm the surface chosen in SKILL.md step 1 actually works for **writes** in this migration:

- **MCP**: usually fine — inherits the operator's session permissions.
- **CLI / API**: confirm the active token has `api_write`. Use `mw user get` to validate auth; check `GET /v2/users/self/api-tokens` for the active token's `roles`. If it's `api_read` only, ask the operator for a writable token before proceeding — provisioning will fail otherwise (Pitfall #21).

A `403` later on is almost never a missing endpoint; it's almost always a missing scope. Don't write doc workarounds around 403s — fix the token.

## 0. Classify the source

Ask the operator (or infer from CWD if obvious):

- **Kubernetes** — kubeconfig context, namespace(s)?
- **Docker / Docker Compose** — host SSH access, compose file path?
- **Bare-metal / VPS** — SSH access, systemd units? plain processes?
- **Managed hoster** (Hetzner Cloud, AWS, GCP, Azure) — which services are managed (RDS, S3, etc.) and which are self-hosted on instances?
- **Another mStudio project** — source `projectId`, can we use Mittwald MCP on both ends?

Record this. Every later step branches on it.

## 1. Service inventory

Collect a **list of running components**. Each entry: name, container image (or binary + version), purpose, public/internal, ports.

| Source | Command |
|---|---|
| Kubernetes | `kubectl -n <ns> get deploy,sts,ds,svc,ingress -o wide` |
| Docker Compose | `docker compose ps`; read the compose file |
| systemd | `systemctl list-units --type=service --state=running` |
| Plain processes | `ss -tlnp` + `ps auxf` |

For each entry, ask: **does this need to move, or is it managed-elsewhere and stays?** (e.g. external Postgres at a hyperscaler may stay; if it doesn't, the migration plan must include it.)

## 2. Data inventory

This drives the downtime budget. Measure **real bytes**, not allocations (Pitfall #12).

### Databases

For each DB engine, capture: version, list of databases, per-DB size, extensions installed (Postgres only — Pitfall #6).

If the source is a common CMS (WordPress, TYPO3, Shopware), DB credentials, base-URL fields, and version-detection paths are catalogued in [`../references/cms-quirks.md`](../references/cms-quirks.md). Use that as the starting point.

**PostgreSQL:**

```sql
SELECT version();
SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database
  WHERE datname NOT IN ('template0','template1','postgres') ORDER BY pg_database_size(datname) DESC;
SELECT extname, extversion FROM pg_extension ORDER BY extname;
```

**MySQL / MariaDB:**

```sql
SELECT VERSION();
SELECT table_schema AS db, ROUND(SUM(data_length+index_length)/1024/1024,1) AS mb
  FROM information_schema.tables
  WHERE table_schema NOT IN ('mysql','information_schema','performance_schema','sys')
  GROUP BY table_schema ORDER BY mb DESC;
```

Also note: are there long-running migrations baked into the app start? (They'll re-run on the target after restore.)

### Files / Volumes

For each persistent path, capture: mount path, real size, file count, "hot" (constantly written) vs "cold" (rarely written).

| Source | Command |
|---|---|
| K8s pod | `kubectl exec <pod> -- du -sh /path && find /path -type f \| wc -l` |
| Compose host | `du -sh /var/lib/docker/volumes/<vol>/_data` |
| VPS | `du -sh /srv/<app>` |

**Watch out for "index" volumes** that are populated on demand (Solr, Elasticsearch, generated caches — Pitfall #11). If `du` shows them small or empty, do not waste time copying them; let the target rebuild on first start.

### Release-symlink layouts (Deployer / Capistrano)

PHP/Ruby sources deployed with **Deployer** or **Capistrano** use a release-rotation layout: `current/` is a symlink to the active `releases/<timestamp>/`, and persistent data (uploads, `.env`, logs) lives in `shared/`, symlinked into each release. Spot it during the file inventory — `ls -l` on the app root shows `current -> releases/<ts>`.

Migrate the **active state only**, not the machinery:

- **Don't** copy the whole tree — `releases/` holds N old deploys and multiplies the data.
- **Don't** ship the symlinks as-is — they'd land as broken links on the target.
- **Do** transfer from `current/` with `tar -h` (dereference): the active release *and* the `shared/` content it links to come across as one flat tree, into the target's single document root. You do **not** rebuild the `current`/`releases`/`shared` scaffolding on mStudio. Mechanics: [`migrate-files.md`](migrate-files.md).

(If the operator wants to keep deploying *to* mStudio with Deployer afterwards, that's a separate post-migration setup — out of scope for the data move.)

### External object storage / S3

If the app uses S3 / MinIO / Backblaze / equivalent: capture bucket names, region, total size, number of objects. Decision point: keep on the original provider (often the cheapest path) or move to Mittwald-attached storage / a project-mounted bucket. Often: **keep**.

## 3. Network surface

- **Domains** the app currently serves. Note whether each is fronted by Cloudflare / Bunny / Fastly. (Pitfall #10 — Cloudflare proxy interferes with Let's Encrypt HTTP-01.)
- **TLS certificates** — Let's Encrypt or commercial? Expiry?
- **Inbound ports** other than 80/443 (mail, SSH, custom protocols).
- **Outbound dependencies** — payment providers, SMTP relays, OAuth, webhooks. The target's egress IP differs; consider IP allowlists at the partners.

## 4. Secrets and config

Enumerate:

- Environment variables (filter `.env`, K8s `Secret`/`ConfigMap`, systemd `EnvironmentFile`).
- Files containing secrets (private keys, JWT keys, OAuth client secrets).
- **Things that change on migration**: DB hosts, redis hosts, SMTP relays. Build a "rewrite map" the operator can sanity-check.
- For common CMS, base-URL / site-URL / shop-domain fields **live in both the config file *and* the DB** and can disagree — they belong in the rewrite map explicitly. See [`../references/cms-quirks.md`](../references/cms-quirks.md) for per-CMS locations and CMS-specific multisite traps (Pitfall #24).
- For PHP-based apps, capture the source's **php.ini** values that the workload actually depends on: `memory_limit`, `upload_max_filesize`, `post_max_size`, `max_execution_time`, `date.timezone`, `opcache.*`, and any non-default `extension=…`. Also note whether the source ships a **`.user.ini`** in the docroot — if yes, it migrates with the code and the values may need a target-side adjustment for Mittwald's defaults. On Mittwald the settings go in a `php.d/*.ini` drop-in under `/home/<p-shortId>/.config/php/php.d/` (project-wide) or a `.user.ini` in the app directory (per-app) — see [`provision-target.md`](provision-target.md) §3a "PHP runtime config". A missing `memory_limit` bump is the most common post-cutover surprise.

Never paste secret values into the conversation. Refer to them by name.

## 5. Background jobs

- Cron entries (`crontab -l`, K8s `CronJob`, systemd timers).
- In-app schedulers / queue workers / Sidekiq / Celery — these usually transplant unchanged but capture their service definitions.
- Note jobs that **must not run** during migration (Pitfall #15: don't kill the source's backup cronjobs prematurely — they're rollback insurance).

## 6. Image sources

For each container image:

- Public registry path (e.g. `library/postgres:15.6`) — works on Mittwald out of the box.
- Private registry — operator must push to Mittwald Project Registry first (Pitfall #14). Mark these as **blockers** for the Provision phase.
- Self-built images without a registry — operator needs to build & push.

## 7. Catalog self-check (live query — do not skip)

Before recommending a target shape, **query the live Mittwald app catalog** and propose how the discovered source maps onto it. The catalog changes; don't reason from memory. Full procedure in [`../references/app-catalog.md`](../references/app-catalog.md). Pitfall #18.

Minimum:

1. List the catalog via the available surface — `mw app versions` (no arg), or `mcp__mittwald__mittwald_app_versions` (no arg), or `GET /v2/apps`.
2. Split entries by tag: `"Eigene App"` → runtime/self-managed (PHP, PHP-Worker, Node.js, Python, Static Files), everything else → Managed-App candidates (WordPress, TYPO3, Joomla, Nextcloud, Matomo, Shopware, …).
3. Match the source's primary component against both buckets using the routing matrix in [`../references/app-catalog.md`](../references/app-catalog.md).
4. For the candidate app type, **diff the source version against `app versions <name>`** and surface the result:
   - exact match → ok
   - newer-supported only → flag as **upgrade-required**
   - no compatible version → flag as **blocker** (operator upgrades source, or fall back to Container Stack)
5. If the source already runs as a Managed App on another mStudio project, check whether `mw app copy` (`mcp__mittwald__mittwald_app_copy`) is the cheaper path.

Output of this step is one of:

- "Managed App `<name>` `<version>`"
- "Runtime app `<type>` (PHP / PHP-Worker / Node.js / Python / Static Files)" — for PHP-shaped apps with workers, this is usually **one PHP app + N PHP-Worker apps**
- "Container Stack" — the fallback when nothing in the catalog fits

### 7b. DB-engines self-check (live query)

Same discipline for the data plane. Full procedure in [`../references/database-engines.md`](../references/database-engines.md). The hard rule:

> **Managed DB engines on mStudio are MySQL and Redis. Everything else (Postgres, MongoDB, …) must run as a container.** Confirm this still holds by checking `mw database --help` or that only `/v2/mysql-versions` and `/v2/redis-versions` exist.

For **each DB engine** in the inventory from §2:

1. If the engine is not MySQL and not Redis → **container in the stack**. Stop. This includes **MariaDB**: mirror it to a `mariadb:<major>` container — don't route a MariaDB source to managed MySQL by default (engine swap = explicit operator opt-in; see [`../references/database-engines.md`](../references/database-engines.md) "Default: mirror the source engine").
2. If it is MySQL or Redis → live-query the supported versions:
   - MySQL: `mw database mysql versions` / `mcp__mittwald__mittwald_database_mysql_versions` / `GET /v2/mysql-versions`
   - Redis: `mw database redis versions -p <projectId>` (CLI quirk — projectId required) / `mcp__mittwald__mittwald_database_redis_versions` / `GET /v2/redis-versions`
3. **Filter out `disabled: true` entries.** Those are deprecated and unavailable for new installs.
4. Diff the source version: ok / upgrade-required / blocker (same outcome shape as the app version diff).
5. Record the choice: "managed `<engine> <version>`" or "container `<engine>`".

This decision lands in the inventory below and gets the operator's explicit approval at the §9 decision gate.

## 8. Output: the inventory

Produce a markdown summary and present it to the operator. Template:

```
## Source inventory

**Source type:** <K8s cluster | Docker Compose host | VPS | other mStudio | …>
**Access:** <kubeconfig context / SSH host / mStudio projectId>

### Services
| Name | Image / Binary | Role | Public? |
|---|---|---|---|
| app | registry.example/foo:1.2.3 | web app | yes (foo.example.com) |
| postgresql | library/postgres:15.6 | primary DB | no |
| …

### Data
| What | Real size | Engine | Notes |
|---|---|---|---|
| db `foo` | 4.2 GB | Postgres 15 | extensions: pg_trgm, citext |
| `/srv/foo/uploads` | 18 GB | files | 142k files |
| `/srv/foo/solr-index` | 12 MB | Solr | rebuilt on start — skip |

### Domains
| Domain | TLS | Fronted by | Action |
|---|---|---|---|
| foo.example.com | LE | Cloudflare (proxied) | DNS-only switch during cutover (Pitfall #10) |

### Proposed target shape (from catalog self-check — Pitfall #18)
- App type: Managed App `<name> <version>` | Runtime app `<type>` (+ N PHP-Worker) | Container Stack
- App version-compat: ok | upgrade-required (from `<source-ver>` to `<target-ver>`) | blocker

### DB targets (from DB-engines self-check — Pitfall #18)
| Source engine | Source version | Target | Reason |
|---|---|---|---|
| MySQL | 5.7 | managed MySQL 5.7 | exact match, non-disabled |
| MariaDB | 10.11 | container `mariadb:10.11` | mirror source engine — MariaDB ≠ managed MySQL |
| Redis | 7.0 | container `redis:7.0` | 7.0 is `disabled: true`, source operator doesn't want to upgrade |
| Postgres | 15.6 | container `library/postgres:15.6` | no managed Postgres on mStudio |

- Reasoning summary: <one-liner>

### Blockers before Provision
- [ ] Push `registry.example/foo:1.2.3` to Mittwald Project Registry
- [ ] Confirm DB has no unmigrated schema changes pending

### Estimated downtime
~<X> min based on <Y> GB of data and <observed throughput>
```

## 9. Decision gate

End the phase with an explicit `AskUserQuestion` (or its non-Claude equivalent) that asks the operator to **approve the inventory** or correct it. Do not proceed to Provision until approved.

## Pitfalls referenced in this phase

- #1 ID hygiene — start tracking IDs cleanly from day one
- #6 Postgres extensions — capture the list now so the target plan can address them
- #10 Cloudflare-proxied DNS — flag for the cutover plan
- #11 Index volumes might be empty
- #12 `du`-based sizing, not PVC size
- #14 Private images need a registry push
- #15 Don't kill source backup jobs yet
- #18 Catalog is queried live, never assumed; don't confuse `app_list` (installed) with `app_versions` (catalog)
- #21 Token scope: a 403 is a scope problem, not a missing endpoint — fix the token, don't route around it
- #23 WordPress plugin lockouts and path mismatches (WP-Hide-Login, Wordfence, cache plugins) — enumerate active plugins now
- #24 Multisite installation hidden in DB/config — detect before sizing the migration
