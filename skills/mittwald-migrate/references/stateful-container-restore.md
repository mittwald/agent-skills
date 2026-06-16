# Pre-loading data into a stateful container before first start

A workaround pattern for stateful containers (Solr indices, search blobstores, app-specific data dirs, anything where "start with empty data and let the app import" isn't an option). Hacky on purpose — see [§ Why this is hacky](#why-this-is-hacky) at the bottom.

Cross-references: Pitfalls [#3](pitfalls.md), [#4](pitfalls.md), [#11](pitfalls.md), [#19](pitfalls.md).

## The problem chain

You want to migrate a stateful container (e.g. weclapp's Solr index, a custom blob store). The data exists on the source as files. You need it in place on the target **before the container starts**, because:

- The container's first start initializes/locks the data directory. Writing into it while running causes index corruption, half-written segments, or the app refusing to mount the dir.
- An empty first start often *seeds* the directory with new metadata, which then prevents a restore from succeeding.

So you need to **write data into the container's mount point while the container is stopped**. That's where four facts collide:

1. **Container-SSH only works on running containers** (Pitfall #3). A stopped container has no shell to SSH into.
2. **Project-Host-SSH** is the alternative — but it can only see paths exposed as **bind-mounts** under `/files/...`. Compose **Named Volumes** (`pgdata:/var/lib/postgresql/data`) live inside the container runtime and are invisible from the project host (Pitfall #4).
3. **Project-Host-SSH is App-bound.** The SSH address is `user@account@a-XXXXX@ssh.<host>.project.host` — the `a-XXXXX` is an **app installation's** short-ID. If the project has *only* container stacks and no app installation, there is no `a-XXXXX` to bind to → no Project-Host-SSH at all.
4. **Compose service short-IDs are `c-XXXXX`** (container), not `a-XXXXX` (app). So a "stack only" project genuinely has no way to land a Project-Host-SSH session.

The workaround threads all four needles.

## The workaround in one paragraph

Lay the stateful container's data path out as a **bind-mount** under `/files/<dummy-app-shortname>/<purpose>` (not a Named Volume). Install a **minimal dummy app** (e.g. `mw app create static`) purely to create an `a-XXXXX` you can SSH into. Via Project-Host-SSH, **`mkdir -p` the bind-mount path and `chmod 777` it** (Pitfall #20 — rootless containers can't chown their mount on first start). **Then** deploy the stack. Stop the stateful container, write data into the now-prepared bind-mount via Project-Host-SSH, start it again. If uid/gid alignment matters, Container-SSH into it after start and `chown` once.

## Step-by-step

### 0. Decide if you even need this

You don't need it when:

- The data path is rebuildable (e.g. pure search index that the app reconstructs from the DB on start) — **skip** that path entirely, see Pitfall #11.
- The app provides an import API that the running container can drive (`LOAD DATA INFILE`, `pg_restore` connected to a running Postgres, S3 sync, app-specific bulk-loader) — use that instead. It's strictly nicer than this workaround.
- The container's image supports an entrypoint hook (`docker-entrypoint-initdb.d` for Postgres, etc.) — pre-seed via that mechanism if available.

You **do** need it when none of the above apply. Stateful containers with binary on-disk formats (Solr/Lucene segments, BoltDB files, a custom blobstore's flat-file layout, etc.) are the typical case.

### 1. Plan the compose layout

For every stateful container that needs offline pre-loading, the mount **must be a bind-mount under `/files/...`**, not a Named Volume:

```yaml
services:
  solr:
    image: solr:9
    volumes:
      - /files/myapp/solr-data:/var/solr/data    # bind-mount — reachable from Project-Host-SSH
      # NOT: solrdata:/var/solr/data            # named volume — invisible from project host
    # leave running normally; we'll stop it explicitly later
```

Containers that *don't* need offline pre-load can still use Named Volumes (they're the right default for "internal state the operator never touches"). Only the ones receiving pre-loaded data need the bind-mount escape hatch.

### 2. Make sure an `a-XXXXX` exists (install the dummy app if needed)

If the project already has at least one app installation (e.g. the Migration is to an mStudio-Managed-App-plus-Stack hybrid), you already have an `a-XXXXX`. Skip to step 3.

Otherwise, install a minimal Static-Files app — cheapest option, no runtime overhead:

```bash
mw app create static -p <projectId> [--hostname <some-throwaway>]
# capture the resulting a-XXXXX from `mw app list -p <projectId>`
```

The dummy app does nothing except exist. It can be uninstalled later if you don't want it lingering, but it costs almost nothing to leave in place — and keeping it means Project-Host-SSH stays available for future operational tasks.

### 3. Pre-create the bind-mount directory and open its permissions

**This is Pitfall #20.** Rootless containers can't `chown` their mount point on first start. If the directory doesn't exist (or exists with the wrong owner), the container crash-loops with `EACCES` before it can do anything useful.

Via Project-Host-SSH using the dummy app's `a-XXXXX`:

```bash
DUMMY_SSH='user@account@a-DUMMYAPP@ssh.<host>.project.host'
DATA_DIR=/files/myapp/solr-data

ssh "$DUMMY_SSH" "mkdir -p '$DATA_DIR' && chmod 777 '$DATA_DIR'"
```

`chmod 777` is intentionally broad here — you usually don't know the container's runtime uid until it has started once. Tighten later (step 7).

If you happen to know the image's runtime uid (common ones: Solr `8983`, Postgres official `999`, MySQL official `999`, `www-data` `33`/`82`, `node` `1000`), prefer `chown` over `chmod` from the start — same effect, narrower attack surface:

```bash
ssh "$DUMMY_SSH" "mkdir -p '$DATA_DIR' && chown 8983:8983 '$DATA_DIR'"
```

### 4. Deploy the stack, then stop the stateful container

```bash
mw stack deploy -c docker-compose.yml -p <projectId>
# wait for stack to come up
mw stack ps -s <stackId>
# stop only the stateful container — it must be offline while we write into its data dir
mw container stop <c-XXXXX-of-stateful-container>
```

Because the bind-mount directory was pre-created with open permissions in step 3, the container starts cleanly. After stopping it, the path is **free for writes** — no process holds locks on it.

> **Edge case.** Some images write initialization files into their data dir on first start. If those interfere with your import (e.g. an empty `lock` file, a marker file that triggers "already initialized" logic), `rm -rf "$DATA_DIR"/*` via Project-Host-SSH before writing the imported data. Confirm with the app's docs that this is safe.

### 5. Write the data into the bind-mount via Project-Host-SSH

```bash
set -Eeuo pipefail

# DUMMY_SSH + DATA_DIR from step 3

# stream from source — example uses tar over SSH
tar -C /srv/solr/data -cf - . \
  | ssh "$DUMMY_SSH" "tar -C '$DATA_DIR' -xf -"
```

This is the same shape as [`../playbooks/migrate-files.md`](../playbooks/migrate-files.md); the only difference is which `a-XXXXX` you authenticate against. The dummy app is purely a routing token — it doesn't see or care about the data.

### 6. Start the container

```bash
mw container start <c-XXXXX-of-stateful-container>
mw container logs <c-XXXXX-of-stateful-container>   # watch for "loaded N segments" or equivalent
```

If the app refuses to come up (corrupt segments, wrong permissions, version mismatch), the logs will tell you. Fix the data in place (Project-Host-SSH again, container still stopped — re-stop if needed) and retry.

### 7. Fix ownership inside the container (optional but recommended after `chmod 777`)

Project-Host-SSH wrote the files as the project-SSH-user's uid, and the directory still has `chmod 777` from step 3. If you'd rather narrow that down — and you should, unless you have a reason not to — Container-SSH into the now-running container and re-own:

```bash
# Container-SSH into the now-running stateful container
ssh user@account@<c-XXXXX>@ssh.<host>.project.host
# inside the container, as the container's runtime user:
id                              # confirm uid (e.g. 8983 for solr)
chown -R "$(id -u):$(id -g)" /var/solr/data
chmod -R 700 /var/solr/data
```

Some apps require this for security policies (e.g. Solr refuses to start with world-writable data); most tolerate the loose permissions but it's good hygiene either way.

If you `chown`'d to the known uid in step 3 instead of `chmod 777`, you can skip this step entirely.

### 8. Verify

- File count matches source (`find /var/solr/data -type f | wc -l` inside the container vs the source).
- App-level health check passes (Solr's `/solr/admin/cores?action=STATUS`, app's `/health` endpoint, whatever applies).
- A query the operator knows returns plausible results (smoke test on the default `<shortId>.project.space` URL — Pitfall #17).

## When this isn't needed

- **Rebuildable indices** (pure caches) — skip the migration, let the app rebuild on first start (Pitfall #11).
- **App provides an import API** — drive the running container with the app's own bulk-load. Cleaner; no workaround needed.
- **DBs (Postgres, MySQL, Redis)** — these have their own dump/restore tooling and the existing playbooks ([`../playbooks/migrate-postgres.md`](../playbooks/migrate-postgres.md), [`../playbooks/migrate-mysql.md`](../playbooks/migrate-mysql.md)) handle them through Container-SSH while running. Only reach for this pattern when the app's native data path doesn't have a "running ingest" mode.

## Why this is hacky

It is. Three things would make it unnecessary:

1. **SSH into stopped containers.** If Mittwald exposed a "shell on the container's filesystem without booting PID 1" mode (think `docker run --rm -it --volumes-from <stopped-c> alpine sh`), no dummy app needed.
2. **Project-host access to Named Volumes.** If `/var/lib/mittwald-volumes/<volname>/` were visible from Project-Host-SSH, named volumes could be pre-loaded directly.
3. **Project-Host-SSH without an app installation.** A "no-app" SSH mode on the project host would remove the dummy-app requirement.

None of these exist today (as of writing). If any of them ship, simplify this pattern — drop the dummy-app indirection and update Pitfall #19.

In the meantime, the workaround works reliably. The dummy Static app costs ~nothing to keep in place between migrations.

## Pitfalls referenced

- **#3** SSH modes — Container-SSH dies on stopped containers.
- **#4** Bind-mounts vs Named Volumes — Project-Host-SSH only sees bind-mounts.
- **#11** Don't migrate rebuildable index volumes — sometimes you can skip this pattern entirely.
- **#19** The pattern itself, in short form.
- **#20** Rootless container needs the bind-mount pre-created with open (or correctly-owned) permissions before first start.
