# Playbook: Rollback

**Goal:** undo the migration cleanly at whatever phase it failed. Read the relevant section based on **where** the migration is currently stuck.

The cardinal rule: the source is the rollback target. Don't decommission it during this skill. Pitfall #15.

## Rollback by phase

### During Discovery / Plan / Provision

Nothing on the source has changed. On the target:

- `mcp__mittwald__mittwald_stack_delete` — removes the stack and its containers.
- `mcp__mittwald__mittwald_domain_virtualhost_delete` — for each virtualhost created.
- `mcp__mittwald__mittwald_project_delete` — **only if the project was created for this migration**. Don't delete a project that the operator already used for other workloads.

Operator-visible cost stops as soon as resources are deleted. No data movement happened; nothing to clean on the source.

### During Migrate (DB or files), source app still scaled to 0

- **DB target dirty**: drop+recreate the target DB (see migrate-postgres.md §3 / migrate-mysql.md §4b). Source-side dump file under `/files/.../<engine>-dumps/` can stay for re-attempt or be deleted.
- **Bind-mount target dirty**: SSH to project host (Project-Host-SSH), `rm -rf /files/myapp/uploads/*` (confirm path **carefully**), redo from `migrate-files.md`.
- **Source comes back up**: scale source app back to its previous replica count, restart workers. Source is authoritative again.

The downtime window was opened — communicate that it's reopening (source is live) and that the cutover is postponed.

### During Verify (smoke test fails)

You haven't flipped DNS. The Mittwald stack is broken in some way; the source is still scaled to 0 but unmodified.

Two options:

1. **Fix forward**: debug the stack (`container_logs`, env vars, missing config). Re-run migration if data is the problem. Most operators want this.
2. **Abort**: scale source back up, leave Mittwald stack in place for next attempt. Source goes live again on its old IP — no DNS change yet, so users were never affected.

Either way, **document the failure mode** in the inventory before retry. Many failures repeat unless the root cause is found.

### After Cutover (DNS flipped, problem discovered)

This is the high-stakes scenario. Choose **fast revert** or **fix forward** within minutes — every minute of degraded service is operator-visible.

#### Fast revert: flip DNS back

Prereqs (all should be true if §1 of `cutover-dns.md` was followed):

- TTL is low (60-300s).
- Source services are scaled to 0 but otherwise intact.
- No writes have landed in the new target's DB (or you're willing to lose them).

Steps:

1. **Re-point A/AAAA records** to the source's IP (the value before cutover — the operator should have captured this).
2. **Re-scale source services** to previous replicas. K8s: `kubectl scale --replicas=N`. Compose: `docker compose up -d`. systemd: `systemctl start …`.
3. **Wait for DNS propagation**: ~TTL seconds. Verify with `dig` from multiple resolvers.
4. **Stop writes on the Mittwald target** to prevent confusion: `mcp__mittwald__mittwald_container_stop` for the `app` service (leave DB up for forensic dumps).
5. **Communicate**: incident is closed, source is live again, post-mortem on the Mittwald-side failure.

#### What about writes that landed on Mittwald?

Between cutover and rollback, the new target might have served traffic and accepted writes. Those writes don't exist on the source.

Options:

- **Accept the data loss** (only viable if traffic volume during the window was small and reversible — operator decides).
- **Export and re-merge**: dump the Mittwald DB after the rollback, identify rows written in the cutover window (timestamp-based), insert them into the source DB. Application-specific; this skill cannot automate it.
- **Don't roll back**: if too many writes landed, the right move is forward — fix the Mittwald-side problem in place rather than reverting and losing data.

The trade-off is time-sensitive. Surface it as `AskUserQuestion` immediately when rollback is being considered.

### Decommission window

The skill defines "fully migrated" as **operator-confirmed after T+N days** (default 14). Until then:

- Source remains scaled-to-0 but reachable to an operator with credentials.
- Source backups continue (Pitfall #15).
- Mittwald project's own backups run (`mcp__mittwald__mittwald_backup_create` taken at cutover; consider a `backup_schedule_create` for daily).

After the operator says "fully migrated":

- Source: archive backups, then stop services / delete deployments. **The operator does this manually** — this skill does not delete source-side resources.
- Mittwald: keep backup schedule; raise DNS TTLs back to normal.

## Backups as rollback insurance

```text
mcp__mittwald__mittwald_backup_create        # one-shot backup of the project
mcp__mittwald__mittwald_backup_schedule_create # daily/weekly
mcp__mittwald__mittwald_backup_list
mcp__mittwald__mittwald_backup_get
```

Take a backup **at cutover** (pre-public-traffic), then nightly. A backup is faster to restore from than re-running the migration from source.

## Confirmation rule

Every rollback step that mutates state — scale up, DNS revert, `container_stop`, drop+recreate — needs an explicit operator confirmation. Rollbacks are stressful; **confirmation gates protect against panic-induced mistakes**.
