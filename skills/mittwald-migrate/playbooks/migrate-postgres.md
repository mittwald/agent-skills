# Playbook: Migrate PostgreSQL

**Goal:** move PostgreSQL data from the source into a `library/postgres:<version>` container on the Mittwald stack, with no schema drift and verifiable row parity.

> **There is no managed Postgres on mStudio.** Only MySQL and Redis are managed engines; Postgres always runs as a container in the stack. See [`../references/database-engines.md`](../references/database-engines.md).

Entry condition: Provision phase complete. Target stack is up, `postgresql` service is `running`, the bind-mount `/files/<app>/postgres-dumps/` exists on the project host.

## 0. Pre-flight

- Confirm target Postgres major version **matches the source** (`SELECT version();` on each). Cross-major migrations need a `pg_upgrade` step or a logical dump that's beyond this playbook.
- Capture the **list of extensions** in use on the source. Pitfall #6: the `library/postgres` image lacks many managed-Postgres extensions; non-load-bearing ones produce noisy errors that are not fatal.
- Confirm the target DB is **expected to be empty**. Pitfall #7: the container's first start created an empty DB you'll drop and recreate.

## 1. Freeze writes on the source

The downtime window opens here. Take the source app offline so the dump is consistent:

| Source | Action |
|---|---|
| Kubernetes | `kubectl -n <ns> scale deploy/<app> --replicas=0` (also any worker deploys) — Pitfall #5 |
| Docker Compose | `docker compose stop app worker` (leave the DB up) |
| systemd | `systemctl stop <app>.service` |

Leave the **DB running** — you still need to dump from it.

## 2. The streaming pipeline (common case)

One copy-pasteable command, then a breakdown. Customize the bracketed parts.

```bash
set -Eeuo pipefail

# --- bracketed values --------------------------------------------------------
SRC_DB_HOST=postgresql.source                       # how to reach source DB
SRC_DB_NAME=appdb
SRC_DB_USER=appuser
TGT_PROJ_SSH='user@account@a-XXXXX@ssh.<host>.project.host'
TGT_DUMP_PATH=/files/myapp/postgres-dumps/appdb-$(date +%Y%m%d-%H%M%S).pgc
# -----------------------------------------------------------------------------

PGPASSWORD="$SRC_DB_PW" \
  pg_dump \
    -h "$SRC_DB_HOST" -U "$SRC_DB_USER" -d "$SRC_DB_NAME" \
    -F c -Z 6 --no-owner --no-acl \
  | ssh "$TGT_PROJ_SSH" "cat > $TGT_DUMP_PATH"
```

**Breakdown.**

- `set -Eeuo pipefail` — Pitfall #8. Without it, a `pg_dump` failure mid-stream is invisible.
- `pg_dump -F c` — custom format. Compressed, restorable with `pg_restore`, allows selective restore.
- `-Z 6` — gzip level 6 inside the dump. Higher = smaller, slower; 6 is the well-trodden default.
- `--no-owner --no-acl` — strip ownership and ACL metadata. The target user is `appuser`, not the source's, so re-applying ownership would error.
- `| ssh … "cat > …"` — stream straight into a file on the project host bind-mount. No intermediate disk on your laptop.
- Bind-mount path under `/files/myapp/postgres-dumps/` — Pitfall #4. Make sure the compose layout mounted this path **into** the postgres container as well (`/files/myapp/postgres-dumps:/dumps:ro` is a common choice).

**Variants.**

- **Source is Kubernetes** with no direct DB access from your laptop: `kubectl exec` into a helper pod and dump from there:

  ```bash
  kubectl -n <ns> exec -i deploy/db-helper -- \
    pg_dump -h postgresql -U appuser -d appdb -F c -Z 6 --no-owner --no-acl \
    | ssh "$TGT_PROJ_SSH" "cat > $TGT_DUMP_PATH"
  ```

- **Source is another mStudio project**: `ssh source-project-ssh 'pg_dump …' | ssh target-project-ssh 'cat > …'`.
- **Want a progress bar**: insert `| pv -terab |` between dump and ssh — Pitfall #9, optional.

## 3. Restore on the target

SSH into the `postgresql` **container** (Pitfall #3: Container-SSH, not Project-Host-SSH):

```bash
ssh "user@account@<postgresql-container-shortId>@ssh.<host>.project.host"
```

Then:

```bash
# inside the postgres container
DUMP=/dumps/appdb-YYYYMMDD-HHMMSS.pgc          # path as seen from inside the container

# 1) drop+recreate the target DB (Pitfall #7)
psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS appdb;"
psql -U postgres -d postgres -c "CREATE DATABASE appdb OWNER appuser;"

# 2) restore
pg_restore \
  -U postgres -d appdb \
  --no-owner --no-acl \
  -j 4 \
  "$DUMP" 2>&1 | tee /dumps/restore.log
```

`-j 4` parallelizes restore jobs. Bump on bigger DBs; lower if the container is small.

Expect non-fatal errors on extensions and roles. Read them (Pitfall #6) before reacting.

## 4. Post-restore housekeeping

```sql
-- inside psql -U postgres -d appdb
ANALYZE;                                                   -- refresh planner stats
REASSIGN OWNED BY postgres TO appuser;                     -- if any objects landed under postgres
ALTER DATABASE appdb OWNER TO appuser;
```

If the source used `SERIAL` / `IDENTITY` sequences, no action needed — `pg_dump` ships sequence values. If it used a custom sequence-management pattern, verify the next-value matches source.

## 5. Verify

**Row counts (authoritative, Pitfall #13):**

```sql
-- run on both source and target, diff the results
SELECT schemaname, relname, n_live_tup
FROM pg_stat_user_tables
ORDER BY schemaname, relname;
```

Identical → done. Mismatch → investigate before proceeding.

**Spot-check critical tables:**

```sql
SELECT COUNT(*), MAX(updated_at) FROM <critical_table>;
```

Run on both sides, compare.

**Application-level smoke test:** save for the Verify phase against `<shortId>.project.space` (Pitfall #17).

## 6. Rollback paths

- Before restore: deleting the dump file under `/files/.../postgres-dumps/` is harmless; source is still serving (just with app stopped — restart it).
- After a bad restore: drop+recreate `appdb` and re-run from step 3. Dump file is intact.
- After full cutover regret: see [`rollback.md`](rollback.md).

## Pitfalls referenced in this playbook

- #3 SSH modes (Container-SSH for restore, Project-Host-SSH for dump-file landing)
- #4 Bind-mount required for `/dumps`
- #5 Scale source app to 0 (if K8s with RWO PVCs)
- #6 Postgres extension errors are usually non-fatal
- #7 Drop+recreate the initial empty DB
- #8 `set -Eeuo pipefail`
- #9 `pv` optional
- #13 Verify with `n_live_tup`, not bytes
- #17 Smoke test on default domain
