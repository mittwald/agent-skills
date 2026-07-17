---
name: mittwald-migrate
description: Migrate an arbitrary application from an external platform to mittwald mStudio. Use when the user mentions "migrate to Mittwald", "Umzug nach Mittwald", "move to mStudio", "Container Hosting auf Mittwald", "stack_deploy", or asks for help moving a workload (K8s, Docker Compose, VPS, another hoster, another mStudio project) onto Mittwald. Source is open, target is always mStudio.
---

# mittwald-migrate

You are guiding an operator through a migration **to Mittwald mStudio**. The source can be anything (Kubernetes, Docker Compose, bare-metal/VPS, another hoster, another mStudio project) — the **target is always mStudio**.

This skill is a workflow orchestrator: it routes to focused playbooks under `playbooks/` and pulls in shared references from `references/`. Do **not** inline the playbook content here — read them when the relevant phase begins.

## How to run this skill

1. **Detect available surfaces.** The skill can drive mStudio via MCP, the `mw` CLI, or the HTTP API — see [references/mittwald-surfaces.md](references/mittwald-surfaces.md). Probe in preference order:
   - **MCP** — check for `mcp__mittwald__mittwald_*` tools in this session.
   - **CLI** — `command -v mw && mw user get -o json` (logged-in check).
   - **API** — operator can supply an `MITTWALD_API_TOKEN`; spec at `https://api.mittwald.de/v2/openapi.json`.

   Pick the highest-preference one available and announce it. If **none** are available, stop and tell the operator: "No Mittwald surface (MCP, CLI, or API token) is available — I won't guess calls." Stay consistent within a phase; mixing surfaces mid-phase is fine only when one surface lacks a capability (e.g. MCP doesn't stream MySQL dumps — fall back to `mw database mysql dump`).

2. **Open with a phase plan.** Create a TodoWrite list with these six phases (mark only the first as in-progress):
   - Discovery — inventory the source
   - Plan — target shape, downtime budget, rollback
   - Provision — create project, stack, virtualhosts, domains
   - Migrate — move data (DBs, files, secrets)
   - Verify — smoke test against the default `<shortId>.project.space` domain
   - Cutover — DNS swap, decommission window

3. **Confirmation gates.** Before each destructive or externally-visible action, summarize what you're about to do and call `AskUserQuestion`. Never run `DROP`, `DELETE`, container/stack deletion, DNS changes, or anything that mutates the source without explicit approval **for that specific step**.

4. **Idempotency.** On every resume, re-check current state (`project_get`, `stack_list`, `stack_ps`, `domain_virtualhost_list`, `database_*_list`) before acting. A project may already exist; a DB may already have data.

5. **Always smoke-test on the default domain.** Every Mittwald stack gets a `<shortId>.project.space` address with a valid Let's Encrypt cert from the first virtualhost. Use it for verification **before** DNS cutover.

6. **Optional wrap-up — offer to contribute learnings.** When the migration reaches a natural end (Verify passed, Cutover done, or it was rolled back), you *may* offer to draft a short, **fully sanitized** GitHub issue summarizing the migration so the skill improves over time. Read [playbooks/contribute-learnings.md](playbooks/contribute-learnings.md). **Strictly opt-in** (default no, never nag), **no secrets or identifying details ever**, and the operator reviews the exact body before anything is filed. If declined, end silently.

## Phase routing

| Phase | Playbook | When to read it |
|---|---|---|
| Discovery | [playbooks/discover-source.md](playbooks/discover-source.md) | First phase, always. Pulls source inventory regardless of source type. |
| Plan + Provision | [playbooks/provision-target.md](playbooks/provision-target.md) | After Discovery is approved. Decides Managed-App vs Stack, lays out compose, creates project & virtualhosts. |
| Migrate Postgres | [playbooks/migrate-postgres.md](playbooks/migrate-postgres.md) | If source has PostgreSQL. Covers `pg_dump -F c` stream, extension errors, initial-empty-DB drop/recreate. |
| Migrate MySQL | [playbooks/migrate-mysql.md](playbooks/migrate-mysql.md) | If source has MySQL/MariaDB. Decides between Mittwald-managed MySQL vs container MySQL. |
| Migrate Files | [playbooks/migrate-files.md](playbooks/migrate-files.md) | For volume / blob / asset data. Uses Project-Host-SSH + `tar`-over-SSH. |
| Cutover | [playbooks/cutover-dns.md](playbooks/cutover-dns.md) | After Verify passes. DNS swap, Cloudflare quirks, TTL strategy. |
| Rollback | [playbooks/rollback.md](playbooks/rollback.md) | Any time something goes wrong. Always referenced before starting a phase. |
| Wrap-up (optional) | [playbooks/contribute-learnings.md](playbooks/contribute-learnings.md) | At the very end, only if the operator opts in. Offer a sanitized learnings issue. Never mandatory, never any sensitive data. |

## Shared references (read on demand)

- [references/mittwald-surfaces.md](references/mittwald-surfaces.md) — MCP vs CLI (`mw`) vs HTTP API: detection, auth, Rosetta-table for the operations the skill uses, links to the developer portal and OpenAPI spec.
- [references/app-catalog.md](references/app-catalog.md) — live catalog query, runtime-app routing (PHP / PHP-Worker / Node.js / Python / Static), version-compat diff. **Read this during Discovery before recommending a target shape.**
- [references/database-engines.md](references/database-engines.md) — managed DB engines (MySQL + Redis); everything else runs as a container. Live-query versions and filter `disabled` entries.
- [references/cms-quirks.md](references/cms-quirks.md) — per-CMS Discovery cheatsheet (WordPress / TYPO3 sym+composer / Shopware 5/6): config files, URL locations, version detection, plugin/extension traps, multisite detection.
- [references/mittwald-mcp-tools.md](references/mittwald-mcp-tools.md) — which `mcp__mittwald__*` tool for which job, with required params.
- [references/ssh-modes.md](references/ssh-modes.md) — Project-Host-SSH vs Container-SSH, when to use which.
- [references/stateful-container-restore.md](references/stateful-container-restore.md) — workaround pattern for pre-loading data into a stopped stateful container (dummy-app + bind-mount). Pitfall #19.
- [references/pitfalls.md](references/pitfalls.md) — 25 traps from real migrations. **Reference the relevant entry at each step, not as an appendix.**
- [references/compose-templates/](references/compose-templates/) — ready-to-deploy compose snippets for common shapes.

> Playbooks below are written **MCP-first** for readability. If you're driving via CLI or API, translate via [references/mittwald-surfaces.md](references/mittwald-surfaces.md) — the universal rules (explicit `projectId`, confirmation gates, row-count verification) hold regardless of surface.

## Universal rules

- **ID hygiene.** Project-ID (UUID), Stack-ID (UUID), Container-ID (UUID) and the short-IDs (`p-...`, `c-...`, `a-...`) all look different. Before passing any ID to a tool, classify which class it belongs to. (Pitfall #1)
- **Always pass `projectId` (UUID) explicitly** — MCP `projectId` arg, CLI `-p / --project-id`, API path/query param. Do not rely on `mittwald_context_get_session` *or* `mw context set --project-id`; both create stale defaults. (Pitfall #2)
- **Measure data with `du`, not PVC size.** Migration time budgets are based on real bytes. (Pitfall #12)
- **Verify with row counts, not byte sizes.** A freshly restored DB lacks bloat — smaller bytes ≠ data loss. Use `n_live_tup` from `pg_stat_user_tables`. (Pitfall #13)
- **Don't delete the source.** Scale-to-0 or pause backups — never destroy until the operator has lived on the new system for N days. (Pitfall #15)
- **Name a rollback path before starting each phase.** If you can't articulate how to undo it, you're not ready to do it.

## Conversation shape

- After Discovery, present a **summary table** (services, DB sizes, volume sizes, domains, downtime estimate) and ask `AskUserQuestion` to approve the plan or change the approach.
- Use **short status updates** when running long pipelines. The operator can't see your tool output — narrate the meaningful events.
- When MCP / CLI / API return an error, **surface it verbatim** and propose a fix; do not silently retry.
- When data sizes change the strategy (e.g. >50 GB of files → consider rsync-resumable approach instead of single `tar`-stream), flag it as a decision point.

## Out of scope (say so explicitly)

- This skill does **not** cover building Docker images. If the source uses private images, point the operator to the Mittwald Project Registry (Pitfall #14) and let them handle the push.
- This skill does **not** handle data-model migrations (schema changes). It moves data as-is.
- This skill does **not** auto-modify DNS at registrars; it tells the operator the records to set and waits.
