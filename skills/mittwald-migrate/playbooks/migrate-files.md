# Playbook: Migrate file data

**Goal:** move persistent file data (uploads, media, attachments, generated assets that aren't reproducible) from the source onto the Mittwald target.

**Where the data lands depends on the target type (Pitfall #4):**

- **App** (Managed App / runtime app) → under the **project home**, at the app's `installationPath` — `/home/<p-shortId>/html` by default. Read the exact path from the project's `directories.Web` or the app's `installationPath`.
- **Container stack** → a **bind-mount under `/files/<app>/...`** as declared in the compose YAML.

The examples below use `/files/myapp/...` (stack case). For an app target, substitute the project-home path. Entry condition: the target path exists (Provision phase created it), source is in or about to enter the downtime window.

## 0. Decide on a transfer strategy

| Data shape | Recommended approach |
|---|---|
| Few GB, single tree, no resume needed | `tar`-over-SSH stream (default) |
| 50 GB+ or unreliable network, resumable | `rsync` over SSH (or multi-pass) |
| Already in S3-compatible storage | Keep where it is; rewrite the app's bucket config |
| "Index" volumes (Solr / Elasticsearch caches) | **Skip** — let target rebuild on start (Pitfall #11) |

Confirm with the operator which paths transfer and which are skipped before starting.

## 1. Default: `tar`-over-SSH stream

One stream, one fsync at the end, no intermediate disk on either end:

```bash
set -Eeuo pipefail

SRC_PATH=/srv/myapp/uploads                          # on the source
TGT_PROJ_SSH='user@account@a-XXXXX@ssh.<host>.project.host'
TGT_PATH=/files/myapp/uploads                        # on the project host

# create target dir (idempotent)
ssh "$TGT_PROJ_SSH" "mkdir -p '$TGT_PATH'"

# stream
tar -C "$(dirname "$SRC_PATH")" -cf - "$(basename "$SRC_PATH")" \
  | ssh "$TGT_PROJ_SSH" "tar -C '$(dirname "$TGT_PATH")' -xf -"
```

Notes:

- Uses `tar`'s `-C` to set working directory both ends — preserves the intended top-level dir name.
- Add `| pv -s "$(du -sb "$SRC_PATH" | awk '{print $1}')" |` between tars for a progress bar (Pitfall #9, optional).
- Compression usually isn't worth it for already-compressed media (JPEG/MP4). If the data is text-heavy, add `| zstd -3 |` and the inverse on receive — but then plan for double the CPU window.
- **If you're not *on* the source** (pulling over SSH from a remote host), make source SSH non-interactive first — password via `sshpass -e`, unknown host key via `-o StrictHostKeyChecking=accept-new` — or the pipeline stalls on a prompt with no TTY (Pitfall #28; [`../references/ssh-modes.md`](../references/ssh-modes.md) § "Source-side SSH access").

**Alternative to hand-assembling the SSH address: `mw app exec`.** For an **app** target you can stream into the app dir via `mw app exec` instead of composing the `user@account@a-XXXXX@ssh.…` string yourself — the CLI resolves the app's SSH target. The one sharp edge (Pitfall #26): `mw app exec COMMAND` runs a **single positional argument**, so wrap anything with pipes/redirects in `bash -c`:

```bash
tar -C "$(dirname "$SRC_PATH")" -cf - "$(basename "$SRC_PATH")" \
  | mw app exec -i <a-XXXXX> -q "bash -c 'tar -C /html -xf -'"
```

`-q` suppresses the CLI's own chatter so it doesn't corrupt the stream (this is a mutation command — it has no `-o json`, Pitfall #27).

**Source is in Kubernetes** (volume mounted in a pod):

```bash
kubectl -n <ns> exec -i deploy/<app> -- \
  tar -C /srv/myapp -cf - uploads \
  | ssh "$TGT_PROJ_SSH" "tar -C '/files/myapp' -xf -"
```

Reminder: with a RWO PVC the pod must be running for `exec` to work — or use a helper pod after scaling the app to 0 (Pitfall #5). Decide which.

## 2. Resumable variant: `rsync`

For datasets where a re-attempt cost is high:

```bash
set -Eeuo pipefail

rsync -aHv --delete-after --info=progress2 \
  -e "ssh" \
  /srv/myapp/uploads/ \
  "$TGT_PROJ_SSH:/files/myapp/uploads/"
```

Flag rationale:

- `-a` — archive (preserves perms, symlinks, timestamps).
- `-H` — hard links preserved (matters for some image libraries).
- `--delete-after` — make target a mirror, but only after a complete pass. Don't use during the first transfer if the target was pre-seeded with anything important.
- `--info=progress2` — single-line summary of overall progress.
- **No `-z`**: media doesn't compress.

For very large trees, do **two passes**: first pass while source is live (best effort, may take hours), second pass after the source app is stopped (delta only — fast).

## 3. Permissions and ownership inside the container

Mittwald containers run **rootless** — they cannot `chown` their bind-mount on first start (Pitfall #20). Two distinct moments matter:

**Before first stack_deploy** (Provision phase, but worth re-stating here): the bind-mount directory must already exist with permissions the container can write to. Either `chmod 777` (broad, fine for paths not shared between containers) or `chown <uid>:<gid>` to the known image uid (Solr `8983`, Postgres official `999`, `www-data` `33`/`82`, `node` `1000`). Done via Project-Host-SSH:

```bash
ssh "$TGT_PROJ_SSH" "mkdir -p '$TGT_PATH' && chmod 777 '$TGT_PATH'"
```

**After the data transfer**: the files now exist but are owned by the project SSH user, not the container's runtime user. Most apps tolerate this (uploads work; the container's process can still read/write because of the `777` from setup). Some apps refuse — typically the ones that check ownership for security policy. To tighten, Container-SSH in (Pitfall #3) after the container is running:

```bash
# inside the app container
chown -R www-data:www-data /var/www/html/uploads
chmod -R 750 /var/www/html/uploads
```

If the compose mounts the bind-mount path with `:ro`, that's wrong for uploads — fix the compose to mount writeable.

## 4. Sanity checks

```bash
# file count
ssh "$TGT_PROJ_SSH" "find '$TGT_PATH' -type f | wc -l"
# total size
ssh "$TGT_PROJ_SSH" "du -sh '$TGT_PATH'"
# random spot check (5 files)
ssh "$TGT_PROJ_SSH" "find '$TGT_PATH' -type f | shuf -n 5 | xargs sha256sum"
```

Compare to source-side numbers. File-count parity is the strongest cheap signal.

For tampering-paranoid workloads:

```bash
# on source
find /srv/myapp/uploads -type f -print0 | sort -z \
  | xargs -0 sha256sum > /tmp/src-checksums.txt
# scp to target host, run the same find+sha256sum, diff.
```

## 5. Special cases

- **Lots of tiny files (10M+ small images)** — `tar`-over-SSH outperforms `rsync` because rsync's per-file overhead dominates. Stick with `tar` unless resumability is essential.
- **Symlinks pointing outside the tree** — `tar -h` follows them (transfers content); without `-h` they ship as broken links on the target. Decide intent first.
- **Sparse files** (rare for upload trees) — `tar --sparse` if needed.
- **Stateful container data** that must land in place **before the container starts** (Solr indices, custom blobstores, on-disk segment formats) — Container-SSH won't work (container is stopped), and Named Volumes aren't reachable from Project-Host-SSH. Use the dummy-app + bind-mount workaround documented in [`../references/stateful-container-restore.md`](../references/stateful-container-restore.md). This is **Pitfall #19**.

## 5b. CMS cache flush (if applicable)

If the migrated app is a common CMS (WordPress, TYPO3, Shopware), clear its cache **after** files land and **before** Verify — stale cache will show old URLs/assets and mask real migration issues. Cache locations and CLI commands per CMS are in [`../references/cms-quirks.md`](../references/cms-quirks.md). WordPress in particular needs special attention to cache plugins (Pitfall #23) — clearing the plugin's cache via its own UI/CLI is the only safe option.

## 6. Rollback paths

- Mid-transfer: cancel the pipeline (Ctrl-C). Target bind-mount has partial data — either retry (idempotent for `rsync`, not for `tar` — restart from scratch) or `rm -rf` and start over.
- Post-transfer but pre-cutover: source is still authoritative. Just retry.
- Post-cutover: see [`rollback.md`](rollback.md).

## Pitfalls referenced

- #3 SSH modes (Project-Host-SSH for write, Container-SSH for chown)
- #4 Where data lives — app target is `/home/<p>/<installationPath>` (default `/html`); stack target is a bind-mount under `/files/`
- #5 RWO PVC requires scale-to-0 for helper-pod path
- #9 `pv` optional
- #11 Skip rebuildable "index" volumes
- #12 Size from `du`, not allocation
- #19 Stateful containers that need offline pre-load — see `stateful-container-restore.md`
- #20 Rootless container: pre-create + chmod the bind-mount before first start; tighten with chown via Container-SSH afterwards
- #23 WordPress cache plugins — clear caches via the plugin's own UI/CLI after URL-rewrite
- #26 `mw app exec COMMAND` is a single string — wrap piped/chained commands in `bash -c`
- #27 `mw app exec` is a mutation command — `-q` (no `-o json`); `-q` also keeps CLI chatter out of the tar stream
- #28 Source SSH must be non-interactive (password via `sshpass -e`, host key via `accept-new`) or a remote pull stalls
