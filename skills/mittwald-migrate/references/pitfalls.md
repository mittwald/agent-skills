# Pitfalls

Real-world traps from prior migrations. Each entry: **symptom → why → fix**. Reference these in-line from the playbooks at the relevant step, not as an end-of-job appendix.

---

## #1 — ID-class confusion

**Symptom.** A tool call fails with "not found" or, worse, mutates the wrong object.

**Why.** Mittwald has at least three classes of identifier in active use:
- **Long UUIDs** for `projectId`, `stackId`, `containerId`, `appId` — used by MCP calls.
- **Short IDs** like `p-laj9z8` (project), `c-si8vdg` (container), `a-edephs` (app) — used in SSH hostnames and the web UI.
- **Customer-facing names** ("WeClapp-Prod", "blog") — used in UI dropdowns.

They look enough alike that they slip past visual review.

**Fix.** Before passing any ID to a tool, classify it. UUIDs are 36 chars with hyphens; short IDs start with a prefix letter and a dash. If the operator hands you "the project ID" and it looks like `p-laj9z8`, resolve it to the UUID with `project_list` first.

---

## #2 — Stale default-project context

**Symptom.** A call operates on the wrong project — typically the previous one the operator was working with.

**Why.** Every Mittwald surface has a "default project" escape hatch that kicks in when no project ID is supplied, and each one can be stale:
- **MCP**: `mcp__mittwald__mittwald_context_get_session` returns a session-default project from the operator's last session.
- **CLI**: `mw context set --project-id=<id>` writes a persistent default to `~/.config/mw/`. Once set, every later `mw …` command without `-p` silently inherits it.
- **API**: no built-in default — but operators sometimes hand-roll wrappers that inject one from an env var.

**Fix.** Always pass the project ID (UUID) explicitly: MCP `projectId` arg, CLI `-p / --project-id`, API path/query param. Treat any default-context mechanism as a hint, not a source of truth. When using `mw` from an agent-run script, never rely on `mw context set` — the next resume of the skill won't see the same context and will silently target the wrong project.

---

## #3 — Two SSH modes, easy to confuse

**Symptom.** "Permission denied" or "host unreachable" trying to SSH into a stopped container.

**Why.** Mittwald exposes two SSH targets per project:
- **Project-Host-SSH**: `user@account@a-XXXXX@ssh.<host>.project.host` — a shell on the project host. Has `/files/...` mounted, can write to bind-mounts.
- **Container-SSH**: `user@account@c-XXXXX@ssh.<host>.project.host` — a shell inside a running container. **Stopped containers are unreachable.**

**Fix.** Pick the right mode for the task. Moving data into a bind-mount? Project-Host-SSH. Running a query inside the app's runtime? Container-SSH. If the container is stopped, Project-Host-SSH is the only option — operate on the bind-mount path.

See `references/ssh-modes.md` for the full address format.

---

## #4 — Where data lives on the project host (apps, stack bind-mounts, named volumes)

**Symptom.** Over Project-Host-SSH you can't find the path you need — `/files/` is empty, a migrated app's files aren't where you expected, or a named volume has no host path at all. Common variants: "where do I drop this DB dump?" and "where did my WordPress files go?"

**Why.** The project host has **three distinct storage areas**, and which one applies depends on what you provisioned:

- **Apps** (Managed Apps + PHP/Node/Python/Static runtime apps) live under the **project home** `/home/<p-shortId>/`. The web root is `/html` by default (the project object's `directories.Web`); an app installed at a custom path uses its `installationPath` (document root = `installationPath` + `customDocumentRoot`). This is **not** `/files`.
- **Container-stack bind-mounts** live under **`/files/<app>/...`** — where a compose `volumes:` bind-mount maps on the project host. Writable from Project-Host-SSH; use for dump transit, uploads, app assets.
- **Container-stack named volumes** (`pgdata:/var/lib/postgresql/data`) are managed by the container runtime — **only the container sees them**. No host path, invisible from Project-Host-SSH. Use for internal state the operator never touches (DB datadir).

**Fix.** Route by what you're targeting:

- **App migration** → `/home/<p-shortId>/<installationPath>` (default `/html`). Read the exact path live from the project's `directories.Web` or the app's `installationPath` (`app_get` / `mw app get`) — don't assume `/html` for a custom install path.
- **Stack, host-reachable path** (dump in transit, uploads) → a **bind-mount under `/files/<app>/...`**, declared in the compose YAML.
- **Stack, internal-only state** (DB datadir) → a **named volume**.

When unsure, `ls /home/<p-shortId>/` and `ls /files/` over Project-Host-SSH before writing. See [`ssh-modes.md`](ssh-modes.md) § "Project-Host-SSH" for the filesystem picture.

---

## #5 — RWO PVC blocks parallel mounts (Kubernetes source)

**Symptom.** Trying to spin up a helper pod to read a volume; pod stays Pending with "volume is already used by pod X".

**Why.** A `ReadWriteOnce` PersistentVolumeClaim can only be mounted by one pod at a time. The running app pod is holding it.

**Fix.** Scale the app deployment to 0 before launching the helper pod:
```bash
kubectl -n <ns> scale deploy/<app> --replicas=0
kubectl -n <ns> wait --for=delete pod -l app=<app> --timeout=120s
# launch helper pod with the PVC
# … do the migration …
# (optional) scale back if you want a rollback target on source side
```
This is the formal start of the **downtime window** — communicate it to the operator before pulling the trigger.

---

## #6 — PostgreSQL extensions on the target

**Symptom.** `pg_restore` prints ERROR lines about missing extensions (`pgaudit`, `set_user`, `pg_stat_statements`, …). Operator panics.

**Why.** Managed Postgres (StackIT, RDS, etc.) often ships extensions the `library/postgres` image doesn't have. The dump file references them. The app itself usually doesn't depend on them — they were operator-facing tooling.

**Fix.** **Read the errors before reacting.** If they're about extensions the app code doesn't call, restore continues and the app works. Document the missing extensions in the inventory and decide explicitly whether to install them on the target (rebuild the Postgres image with them) or accept the loss.

**What is fatal**, by contrast: missing extensions that the schema depends on (e.g. `postgis` types in column definitions). Those `CREATE EXTENSION` failures will cascade into table creation failures. Distinguish.

---

## #7 — Initial empty DB in the Postgres container

**Symptom.** `pg_restore` complains the target DB already exists, or restores into a DB that wasn't quite empty.

**Why.** The `library/postgres` image creates a database on first start, named by `POSTGRES_DB`. By the time you connect to restore, that DB exists and is empty (or nearly so).

**Fix.** Right before restore, connect to the `postgres` administrative DB and drop+recreate the target:
```bash
psql -h postgresql -U postgres -d postgres -c "DROP DATABASE IF EXISTS appdb;"
psql -h postgresql -U postgres -d postgres -c "CREATE DATABASE appdb OWNER appuser;"
```
Then restore into the now-pristine `appdb`. Do **not** run `DROP` on the `postgres` administrative DB itself.

---

## #8 — Hidden pipeline failures without `pipefail`

**Symptom.** Migration "succeeded" but the target DB is empty or partial.

**Why.** In a pipeline like `pg_dump … | ssh host 'cat > dump.pgc'`, the shell reports the exit status of the **last** command by default. If `pg_dump` failed mid-stream, `cat` still exits 0 and the pipeline looks green.

**Fix.** Every script in this skill starts with:
```bash
set -Eeuo pipefail
```
For ad-hoc one-liners typed at the prompt, prepend `set -o pipefail;` to the command.

---

## #9 — `pv` not installed locally

**Symptom.** The pretty progress bar from the runbook isn't there; operator can't tell if the pipeline is making progress.

**Why.** `pv` is a third-party tool not installed by default on macOS, Windows, or many Linux distros.

**Fix.** Don't make `pv` a hard dependency. Write pipelines as `pg_dump … | ssh …`, and offer `pv` as an opt-in wrapper:
```bash
pg_dump … | pv -terabs <expected-size> | ssh …
```
On systems without `pv`, suggest periodic `du -sh` checks on the target file from a second shell.

---

## #10 — Cloudflare proxy breaks Let's Encrypt HTTP-01

**Symptom.** `certificate_request` for the real hostname fails with HTTP-01 challenge errors. The Mittwald virtualhost stays on a self-signed cert.

**Why.** When Cloudflare proxies the hostname (orange cloud), HTTP requests to `/.well-known/acme-challenge/...` hit Cloudflare, not Mittwald. Mittwald can't answer the ACME challenge.

**Fixes (pick one):**
1. **Temporarily set Cloudflare to "DNS only"** (grey cloud) for the hostname, request the cert, switch back.
2. **Cloudflare Origin Certificate** (15-year cert issued by Cloudflare) — upload to Mittwald via `certificate_request` as a custom cert. Public TLS terminates at Cloudflare; Mittwald-to-Cloudflare uses the Origin Cert.
3. **Accept Mittwald serving self-signed** behind Cloudflare — only safe if Cloudflare's SSL mode is "Flexible" or "Full" (not "Full (strict)"). "Flexible" is **not recommended** for any real workload; "Full" tolerates self-signed; "Full (strict)" rejects it.

Document the chosen approach in the cutover plan.

---

## #11 — "Index" volumes that are actually empty

**Symptom.** Volume named `solr-data` or `elasticsearch-data` shows 12 MB. Operator wonders if migration broke something.

**Why.** Many apps rebuild their search index from the primary DB on startup. The volume exists but is repopulated on demand; it's not authoritative state.

**Fix.** During Discovery, check `du -sh` on each "index-shaped" volume. If it's small or empty, skip it in Migration — let the target rebuild on first start. Document the expected post-cutover reindex time so the operator isn't surprised by slow first queries.

---

## #12 — PVC / disk allocation isn't a size estimate

**Symptom.** Operator budgets 4 hours of downtime for a "50 GB volume" that's actually 8 GB on disk.

**Why.** Kubernetes PVCs, cloud block volumes, and partition sizes report allocation, not usage.

**Fix.** Always size migrations from `du -sh` on the actual mount point. For databases, use the engine's own size query (`pg_database_size`, `information_schema.tables`). Capture both numbers in the inventory so the gap is visible.

---

## #13 — Verify with row counts, not bytes

**Symptom.** Operator panics because target DB is 800 MB and source DB is 4.2 GB.

**Why.** A freshly restored DB has no dead tuples, no bloat, optimal page packing. The data is identical; the bytes aren't.

**Fix.** Verify by comparing live row counts:
```sql
SELECT schemaname, relname, n_live_tup
FROM pg_stat_user_tables ORDER BY schemaname, relname;
```
Diff source vs target. A non-zero diff is a real problem; identical counts at smaller bytes is healthy.

(MySQL equivalent: `SELECT table_schema, table_name, table_rows FROM information_schema.tables` — note `table_rows` is approximate on InnoDB; for exact counts run `SELECT COUNT(*)` per table on critical ones.)

---

## #14 — Private image not reachable from Mittwald

**Symptom.** `stack_ps` shows the container in `ImagePullBackOff` / `ErrImagePull`.

**Why.** Mittwald's runtime pulls images during deploy. Private registries (internal GitLab, ghcr.io with private packages, etc.) need credentials Mittwald doesn't have.

**Fix.** Push the image to the **Mittwald Project Registry** before deploy:
```text
mcp__mittwald__mittwald_registry_list
mcp__mittwald__mittwald_registry_create   # if needed
```
Image path becomes `<project-shortId>.project.space/<image>:<tag>`. Push from a host with credentials to both registries:
```bash
docker pull registry.example/foo:1.2.3
docker tag registry.example/foo:1.2.3 <project-shortId>.project.space/foo:1.2.3
docker login <project-shortId>.project.space   # credentials from registry_create
docker push <project-shortId>.project.space/foo:1.2.3
```
Update the compose to reference the new path.

---

## #15 — Don't kill source backups prematurely

**Symptom.** Cutover went wrong; operator wants to roll back; source-side backup jobs were stopped two weeks ago.

**Why.** It's tempting to "clean up" backup cronjobs on the source during cutover. They are often the fastest rollback path — point-in-time restore from a backup taken hours ago is faster than rebuilding.

**Fix.** Leave source backups running through the verification grace window (the agreed N days of post-cutover observation). Decommission them only after the operator explicitly retires the source.

---

## #16 — Service name = hostname within a stack

**Symptom.** App config has `DB_HOST=10.x.x.x` or `DB_HOST=postgresql.default.svc.cluster.local` copied from the source.

**Why.** Mittwald stacks expose service names as resolvable hostnames inside the stack. Whatever you name a service in the compose YAML is its in-stack DNS name.

**Fix.** Rewrite source-side DB hostnames to bare service names: `DB_HOST=postgresql`, `REDIS_HOST=redis`. Capture this in the env-var rewrite map during Discovery.

---

## #17 — Default `<shortId>.project.space` is your smoke-test surface

**Symptom.** Operator wants to verify the migration before DNS cutover, asks where to point a browser.

**Why.** A virtualhost can be created with the final hostname (e.g. `foo.example.com`) even before DNS resolves to Mittwald. Mittwald also serves the same stack on a default domain shaped like `<shortId>.project.space` — that domain always has a valid Let's Encrypt cert and resolves correctly.

**Fix.** Always use `<shortId>.project.space` for smoke tests during Verify. Find it via `domain_virtualhost_list` (it's listed alongside the operator's custom hostname). Test the golden path *and* a few cookie/session flows there before touching DNS.

---

## #18 — Hardcoded catalog assumption / `app_list` vs `app_versions`

**Symptom.** The skill suggests a Managed App or runtime app type that isn't actually offered, runs `app_list` expecting catalog data and gets installed-app data instead (or vice versa), or picks a target version the catalog doesn't support — leading to a failed `mw app install` / `app create` call late in the Provision phase.

**Why.** Two failure modes converge here:

1. **Stale documentation.** The Mittwald app catalog evolves — new runtime apps appear, versions move, deprecations happen. Any list baked into a playbook starts decaying the moment it's written.
2. **Tool confusion.** `mcp__mittwald__mittwald_app_list` is **project-scoped** and returns the apps *installed* in that project. The **catalog** comes from `mcp__mittwald__mittwald_app_versions` (no project context). The CLI mirrors the same split: `mw app list -p …` (installed) vs `mw app versions` (catalog). The API split is `/v2/projects/{projectId}/app-installations` (installed) vs `/v2/apps` (catalog).

**Fix.** During Discovery, run the catalog self-check **live** against the available surface:

- MCP: `mcp__mittwald__mittwald_app_versions` with no `app` argument lists the whole catalog.
- CLI: `mw app versions` (no argument) walks the catalog.
- API: `GET /v2/apps` returns the catalog; `GET /v2/apps/{appId}/versions` returns supported versions for one app.

Use the result to drive the Managed-App-vs-runtime-app-vs-Container-Stack decision *now*, instead of from memory. Diff the source's runtime version against the live `app_versions` list and surface incompatibilities before the operator approves the plan. Full procedure: [`app-catalog.md`](app-catalog.md).

Note: as of this writing the MCP server has **no `app_install` / `app_create` tools** — provisioning a new installation goes through CLI or API. Re-check when the MCP tool list changes.

---

## #19 — Restoring data into a stateful container before first start

**Symptom.** You need to pre-load files into a stateful container's data directory (Solr index, search blobstore, custom on-disk format) before the container starts. Container-SSH refuses because the container is stopped. Trying to start the container "just to SSH in and load data" causes the container to initialize the data directory itself, which interferes with the restore.

**Why.** Four facts collide:

1. Container-SSH only works on **running** containers (Pitfall #3).
2. Project-Host-SSH can only see **bind-mount** paths under `/files/...`. Compose **Named Volumes** are invisible from the project host (Pitfall #4).
3. Project-Host-SSH is **app-bound** — the address requires an `a-XXXXX` (app installation short-ID). A stack-only project has no `a-XXXXX`.
4. Stack container short-IDs are `c-XXXXX`, not `a-XXXXX`. They're not usable as SSH targets to the project host.

**Fix.** Workaround pattern, full walkthrough in [`stateful-container-restore.md`](stateful-container-restore.md). TL;DR:

1. In the compose YAML, mount the stateful path as a **bind-mount under `/files/<dummy-app>/...`**, not a Named Volume.
2. Install a **minimal Static-Files app** (`mw app create static -p <projectId>`) to obtain an `a-XXXXX` purely for Project-Host-SSH access.
3. Deploy the stack, then stop the stateful container (`mw container stop <c-XXXXX>`).
4. Write the data via Project-Host-SSH using the dummy app's `a-XXXXX`. Same shape as the file-migration playbook.
5. Start the container. `chown` inside via Container-SSH if uid/gid matters.

The pattern is intentionally hacky. It can be retired if Mittwald gains SSH-into-stopped-containers, project-host visibility for named volumes, or app-less Project-Host-SSH.

---

## #20 — Rootless container can't write to a bind-mount with default permissions

**Symptom.** Container crash-loops on first start with `EACCES`, `permission denied`, "could not create directory", or "could not write lockfile". The bind-mount path exists on the project host, but the container can't write to it.

**Why.** Mittwald containers run **rootless**. The container process runs as its image's internal user (`solr` uid 8983, `www-data` 33/82, `node` 1000, `postgres` 999/70 depending on the image — every image has its own). The bind-mount under `/files/...` inherits the **project host's** ownership — typically the project SSH user (e.g. `p-XXXXX`). That uid almost never matches the container's internal uid.

Because the container is rootless, it **cannot `chown` the mount point itself** on first start (no `CAP_CHOWN`, no `setuid`). It tries to write, hits the host's permissions, fails.

**Fix.** Prepare the directory **before** the container starts:

1. Make sure an `a-XXXXX` exists for Project-Host-SSH access (install a dummy Static app if there's no app yet — same prerequisite as Pitfall #19).
2. Via Project-Host-SSH, create the directory and open permissions:
   ```bash
   ssh user@account@a-XXXXX@ssh.<host>.project.host \
     "mkdir -p /files/<app>/<data-dir> && chmod 777 /files/<app>/<data-dir>"
   ```
3. **Only then** deploy the stack (`mw stack deploy …`). The container now starts cleanly because it can write into the open directory.
4. (Optional, post-start tightening.) Once the container has started and you can read its runtime uid (`docker inspect` equivalent: `mw container get` / Container-SSH `id -u`), tighten via Container-SSH:
   ```bash
   ssh user@account@c-XXXXX@ssh.<host>.project.host \
     "chown -R <uid>:<gid> /var/data && chmod 700 /var/data"
   ```
   Skip this step if `chmod 777` is acceptable for your threat model — it usually is for paths that aren't shared between containers.

If you know the container's uid in advance (Solr=8983, Postgres official image=999, etc.), prefer `chown <uid>:<gid>` over `chmod 777` from the start — same effect, narrower attack surface:

```bash
ssh user@account@a-XXXXX@ssh.<host>.project.host \
  "mkdir -p /files/<app>/<data-dir> && chown 8983:8983 /files/<app>/<data-dir>"
```

**Order of operations matters.** Stack deploy → container starts → permission error → restart loop is a dead end. Stack delete + permission fix + redeploy works, but it's slower than getting the order right the first time. See also [`stateful-container-restore.md`](stateful-container-restore.md), which assumes pre-prepared directories throughout.

---

## #21 — Token-scope `403` misread as "endpoint not available"

**Symptom.** An API call returns `403 PermissionDenied`. The skill (or operator) concludes the endpoint is internal-only, UI-only, or not exposed via the public API, and silently routes around it via a different surface or a documentation workaround.

**Why.** Mittwald API tokens carry **roles** and **scopes** that gate what they can do. Two coarse roles surfaced in the Studio UI when creating a token:

- `api_read` — read-only across resources the operator has access to
- `api_write` — read + write

Underneath, there are ~45 fine-grained scopes in the `<resource>:<action>` shape (`app:read`, `app:write`, `app:delete`, `backup:read`, `backup:write`, `backup:delete`, etc.). The Studio UI maps the `api_read`/`api_write` choice to a bundle of these scopes.

A `403` means **this token lacks the scope for this action**, not "this endpoint doesn't work via API". In particular, examples that bit this skill during development:

- `GET /v2/users/self/ssh-keys` — needs a token with sufficient user-profile scope (covered by `api_write` bundle in practice). With a read-only token, returns 403 — easy to mistake for "SSH keys are UI-only", which is wrong.
- Various `POST` endpoints — return 403 if the token was created with `api_read` only.

**Fix.** When you hit a 403, **don't conclude "no API"**:

1. List the operator's tokens: `GET /v2/users/self/api-tokens` — each token returns its `roles` array. Confirm the active token's roles match what the operation needs.
2. If the token is under-scoped, ask the operator to issue a new one with the right role at <https://studio.mittwald.de/app/profile/api-tokens>. Re-test the failing call. Most "this endpoint must be UI-only" hypotheses dissolve at this step.
3. If the call still 403s after the token is upgraded, *then* it's likely an actual access-control restriction (you're not a member of that customer/org, the resource doesn't belong to you, etc.) — escalate from there.
4. Available scopes are listable: `GET /v2/scopes` (returns the ~45 entries). Useful when designing a least-privilege token for a specific automation.

**Diagnostic checklist for any 403 in this skill:**
```
1. echo "$MITTWALD_API_TOKEN" | wc -c     # token actually set?
2. curl -sS -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
     https://api.mittwald.de/v2/users/self/api-tokens \
     | jq '.[] | select(.description=="<your-token-description>") | .roles'
3. # if "roles" doesn't include api_write but the endpoint requires it,
4. # re-issue the token. Don't write a UI-only doc workaround.
```

This is the kind of trap that produces lasting documentation rot: "this endpoint is API-internal" gets baked into a reference, and future operators read it as truth even after the underlying restriction (if any) is lifted. Verify before declaring.

---

## #22 — TYPO3 Composer installation: webroot must be `<install>/public/`

**Symptom.** After Provision, the virtualhost serves a 404 on every path. The default `<shortId>.project.space` URL shows the runtime's "no index" page or returns plain 404. The TYPO3 files are clearly on disk but nothing routes.

**Why.** Composer-based TYPO3 installs split the install root into two directories: `<install>/` (vendor, config, var) and `<install>/public/` (the actual webroot containing `index.php`, `typo3/` and assets). Symlink-based TYPO3 doesn't have this split — its webroot is the install root. Operators (and skills) that have only seen symlink-layout TYPO3 wire the virtualhost at `<install>/` and get 404s for everything because `index.php` is one directory deeper.

**Fix.** Set the document root to `<install>/public/` **at Provision time**, not after. The decision lives in two places depending on the target shape:

- **PHP runtime app** (`mw app create php`) — set the install's document-root path to include `public`. Confirm via `mw app get <installationId>` after creation.
- **Container Stack** — the web service (`nginx`/`apache`/`php-fpm` with `caddy`/etc.) must mount and route from `public/`. Compose example:
  ```yaml
  services:
    app:
      image: php:8.2-apache
      volumes:
        - ./typo3-install:/var/www/html              # whole install
      environment:
        APACHE_DOCUMENT_ROOT: /var/www/html/public   # webroot ≠ mount root
  ```

**Identify the layout during Discovery**: a `composer.json` at the install root with `typo3/cms-core` listed, plus a `public/` subdirectory present, signals Composer-based. See [`cms-quirks.md`](cms-quirks.md) § "TYPO3 — Composer-based".

---

## #23 — WordPress plugin lockouts and path mismatches after migration

**Symptom.** Site loads but the operator can't access `/wp-admin` (404 or "this site can't be reached"). Or `/wp-admin` loads but throws fatal errors from a plugin file. Or the site serves clearly stale content that doesn't match the just-migrated DB.

**Why.** Several common WordPress plugins encode environment-specific configuration that breaks when the install moves:

- **WP-Hide-Login** — rewrites `/wp-admin` to a custom path and/or restricts by source IP. After migration the operator's IP isn't on the (old-site) whitelist, or the rewrite rule references a different rewrite engine than what Mittwald uses.
- **Wordfence** — writes absolute paths into `wordfence-waf.php` and `user.ini` based on the source's filesystem layout. Mittwald's layout differs; the WAF fails to load (silent or noisy depending on PHP error display).
- **Cache plugins** (W3 Total Cache, WP Super Cache, LiteSpeed Cache, WP Rocket) — populate their cache directory with rendered HTML referencing the source's URLs and asset paths. Even after a `wp search-replace` on the DB, cached HTML keeps serving the old URLs until purged.

**Fix.** Handle each pre-cutover where possible:

- **WP-Hide-Login**: deactivate via wp-cli (`wp plugin deactivate wps-hide-login`) before cutover, or rename the plugin dir on the source. Update the configured custom URL / IP whitelist on the target before reactivating.
- **Wordfence**: edit `wordfence-waf.php` and `user.ini` to use Mittwald-correct paths, or deactivate Wordfence until those paths are confirmed. The plugin's own UI has a "Reset to defaults" option that helps.
- **Cache plugins**: clear the cache (via the plugin UI, via `wp <plugin> cache clear`, or by `rm -rf` on the cache directory) **immediately after** any DB URL-rewrite. Don't trust the plugin to invalidate on its own — the cache key includes the old URL.

Discovery should enumerate active plugins (`wp plugin list --status=active --format=json`) and flag these three families specifically. See [`cms-quirks.md`](cms-quirks.md) § "WordPress → Plugins that complicate migrations".

---

## #24 — Multisite installation hidden in DB/config

**Symptom.** Migration plan was sized for a single site. After cutover, the primary domain works but secondary domains 404 or all route to the same site. DB sizing was way under what got dumped. Some files/uploads are missing because their per-site subdirectory wasn't migrated.

**Why.** Multisite mode hides in places easy to miss during a casual Discovery:

- **WordPress Multisite**: `define('MULTISITE', true);` in `wp-config.php`; sites enumerated in `wp_blogs` / `wp_site` / `wp_sitemeta`; per-site DB tables prefixed `wp_<id>_*`; uploads partition under `wp-content/uploads/sites/<id>/`.
- **TYPO3 Multisite**: multiple subdirectories under `typo3conf/sites/` (symlink layout) or `config/sites/` (Composer layout), each with its own `config.yaml` and `base:`. DB references via site identifier in `sys_template` and elsewhere.

When the migration plan assumes single-site, the consequences cascade: virtualhost count is wrong (only the primary domain is provisioned), DB-sizing is wrong (managed-DB tier may not fit), the file tree migration misses entire `uploads/sites/<id>/` subtrees, and the URL-rewrite map omits secondary domains.

**Fix.** Detect during Discovery, **before** Plan:

- **WordPress**:
  ```bash
  grep -E "define\\(\\s*'MULTISITE'\\s*,\\s*true" wp-config.php
  # also: SUBDOMAIN_INSTALL, DOMAIN_CURRENT_SITE, PATH_CURRENT_SITE
  # DB-side:
  mysql -e "SELECT blog_id, domain, path FROM wp_blogs;" <db>
  ```
- **TYPO3**:
  ```bash
  ls typo3conf/sites/   # or config/sites/ for Composer layout
  # each subdirectory is one site
  ```

If multisite, re-plan: provision all virtualhosts (one per domain), recompute DB sizing × site count, ensure the file migration covers every per-site subtree, and extend the URL-rewrite map across all sites. See [`cms-quirks.md`](cms-quirks.md) for the per-CMS details.

---

## #25 — SSH / migration started before the app is `phase == "ready"`

**Symptom.** Right after `mw app create` / `mw app install` (or the API equivalent), SSH connections are refused or resolve to "host not found", the app's files (`/home/<p-shortId>/<installationPath>`) aren't there yet, php.ini overrides have nowhere to land, or the first migration step fails with confusing connection errors. Retrying a minute later "magically" works.

**Why.** App provisioning is **asynchronous**. The create/install call returns as soon as the request is accepted, while the installation moves through `phase: pending` → `installing` → `ready` over seconds to minutes (longer for heavier Managed Apps). Until `phase == "ready"`, the runtime, the SSH routing for the app's `a-XXXXX`, and the app's filesystem may not exist. Chaining SSH or migration onto a just-issued create is a race the agent usually loses.

**Fix.** Always wait for readiness before the next step:

- **CLI** — pass `-w / --wait` (with `--wait-timeout`, default `600s`) on the create/install call itself:
  ```bash
  mw app install wordpress -p <projectId> -w --wait-timeout 600s
  mw app create php        -p <projectId> -w --wait-timeout 600s
  ```
- **MCP / API** — there's no wait flag (and MCP can't install at all), so poll:
  ```text
  mcp__mittwald__mittwald_app_get  installationId=<id>   # read .phase
  ```
  The `phase` enum is `pending`, `installing`, `upgrading`, `ready`, `disabled`, `reconfiguring`. Loop until `ready`. Narrate the wait to the operator rather than blocking silently.

Only after `phase == "ready"` do you: establish SSH access (own studio user or per-project `ssh_user_create`), write php.ini overrides, land dumps, or run any migration step. The same applies after `app_upgrade` (transient `upgrading` phase). See [`../playbooks/provision-target.md`](../playbooks/provision-target.md) §3a and [`ssh-modes.md`](ssh-modes.md).
