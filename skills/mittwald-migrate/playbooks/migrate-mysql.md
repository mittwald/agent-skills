# Playbook: Migrate MySQL / MariaDB

**Goal:** move MySQL or MariaDB data into the target. Target may be **(a)** Mittwald-managed MySQL or **(b)** a MySQL container in the stack — decision made during Provision.

## 0. Target shape recap

Decision was made during Discovery's DB-engines self-check ([`discover-source.md`](discover-source.md) §7b; full rules in [`../references/database-engines.md`](../references/database-engines.md)). One of two paths:

| Choice | Pros | Cons |
|---|---|---|
| Mittwald-managed MySQL | Mittwald owns backups, upgrades, monitoring | Limited version flexibility, not in the same stack network |
| Container MySQL in the stack | Full control, same network as app, version-locked | Operator owns backups / upgrades |

Before running `database_mysql_create`, **confirm the chosen version is still in `mw database mysql versions` and not `disabled`** (Pitfall #18). Versions move; a self-check from a week ago might already be stale if the migration was paused.

If using managed MySQL, you already ran `database_mysql_create` + `database_mysql_user_create`. The reachable host comes from `mcp__mittwald__mittwald_database_mysql_get`. The app reaches it via that host; **not** by a service name.

If using container MySQL, the service name is the hostname (Pitfall #16): `DB_HOST=mysql`.

## 1. Freeze writes on the source

Same as Postgres playbook step 1. Stop the application; leave the DB running.

## 2. Dump from the source

`mysqldump` is the workhorse. Flags that matter:

| Flag | Reason |
|---|---|
| `--single-transaction` | Consistent snapshot on InnoDB without locking |
| `--routines` | Stored procedures and functions |
| `--triggers` | Triggers (default but be explicit) |
| `--events` | Scheduled events (if any) |
| `--set-gtid-purged=OFF` | MySQL 5.7+ only; avoids GTID mismatch on restore |
| `--no-tablespaces` | MySQL 8 with PROCESS privilege restrictions on the source |
| `--default-character-set=utf8mb4` | Avoid mojibake when source/target charsets differ |

## 3. The streaming pipeline

```bash
set -Eeuo pipefail

SRC_DB_HOST=mysql.source
SRC_DB_USER=root
SRC_DB_NAME=appdb
TGT_PROJ_SSH='user@account@a-XXXXX@ssh.<host>.project.host'
TGT_DUMP_PATH=/files/myapp/mysql-dumps/appdb-$(date +%Y%m%d-%H%M%S).sql.gz

MYSQL_PWD="$SRC_DB_PW" \
  mysqldump \
    -h "$SRC_DB_HOST" -u "$SRC_DB_USER" \
    --single-transaction --routines --triggers --events \
    --set-gtid-purged=OFF --no-tablespaces \
    --default-character-set=utf8mb4 \
    "$SRC_DB_NAME" \
  | gzip -6 \
  | ssh "$TGT_PROJ_SSH" "cat > $TGT_DUMP_PATH"
```

Notes:

- `gzip -6` matches the trade-off used for Postgres dumps. Drop to `-1` for fastest CPU, `-9` for smallest file.
- `set -Eeuo pipefail` is mandatory (Pitfall #8).

## 4a. Restore — Mittwald-managed MySQL

From any host that can reach the managed MySQL endpoint (your laptop with VPN, a job container, or the project host):

```bash
# get target host from MCP: database_mysql_get → hostname, port
MYSQL_PWD="$TGT_DB_PW" \
  zcat appdb-YYYYMMDD-HHMMSS.sql.gz \
  | mysql -h "$TGT_HOST" -P "$TGT_PORT" -u "$TGT_USER" "$TGT_DB_NAME"
```

If the dump lives on the project host: SSH there first (Project-Host-SSH, Pitfall #3) and run from there.

The managed MySQL DB starts **empty**; no drop/recreate dance is needed. If you've re-run a partial migration, drop the schema objects first:

```sql
-- destructive — confirm with operator first
DROP DATABASE appdb;
CREATE DATABASE appdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

## 4b. Restore — container MySQL

SSH into the `mysql` **container** (Container-SSH, Pitfall #3):

```bash
ssh "user@account@<mysql-container-shortId>@ssh.<host>.project.host"
```

Then, inside:

```bash
DUMP=/dumps/appdb-YYYYMMDD-HHMMSS.sql.gz

# Initial-empty-DB drop+recreate (analog to Postgres Pitfall #7)
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e \
  "DROP DATABASE IF EXISTS appdb;
   CREATE DATABASE appdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   GRANT ALL ON appdb.* TO 'appuser'@'%';"

zcat "$DUMP" | mysql -u root -p"$MYSQL_ROOT_PASSWORD" appdb
```

`MYSQL_ROOT_PASSWORD` is the env you set in the compose for the `mysql` service.

## 5. Post-restore

```sql
-- refresh stats
ANALYZE TABLE <each_critical_table>;

-- confirm character set didn't drift
SELECT @@character_set_database, @@collation_database;
SHOW TABLE STATUS WHERE Name = '<critical_table>';
```

If the source ran InnoDB and the target ended up MyISAM (or vice versa) you have a config drift — investigate before going live.

## 6. Verify

**Row counts.** InnoDB's `information_schema.tables.table_rows` is approximate — use it for a coarse pass, then `SELECT COUNT(*)` on tables the operator cares about:

```sql
-- coarse
SELECT table_schema, table_name, table_rows
FROM information_schema.tables
WHERE table_schema = 'appdb'
ORDER BY table_name;

-- precise (per critical table)
SELECT COUNT(*) FROM <critical_table>;
SELECT MAX(<timestamp_col>) FROM <critical_table>;
```

Compare source vs target.

(Pitfall #13: bytes will not match — restored DBs have less bloat.)

## 7. Rollback paths

- Bad restore on container target: `DROP DATABASE appdb; CREATE DATABASE appdb …`, re-run from step 4b.
- Bad restore on managed target: same DROP+CREATE, run from outside; or `database_mysql_delete` + recreate if state is unrecoverable.
- Full rollback after cutover: see [`rollback.md`](rollback.md).

## Pitfalls referenced

- #3 SSH modes
- #4 Bind-mount under `/files/.../mysql-dumps`
- #5 Scale source app to 0
- #8 `set -Eeuo pipefail`
- #13 Verify by counts, not bytes
- #16 Service name as hostname (container variant)
