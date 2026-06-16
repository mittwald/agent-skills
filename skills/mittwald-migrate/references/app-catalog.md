# App catalog — live query, runtime types, version-compat

The skill never hardcodes which apps mStudio offers. The catalog changes; this file describes **how to ask**, and how to map a discovered source onto a target app type.

Run the catalog self-check **once per migration, during Discovery**, before recommending a target shape. The result feeds the Provision phase.

## Catalog primitives

Across the three surfaces (see [`mittwald-surfaces.md`](mittwald-surfaces.md)):

| Operation | MCP | CLI | API |
|---|---|---|---|
| List the whole catalog (all supported apps) | `mcp__mittwald__mittwald_app_versions` (no `app` arg) | `mw app versions` (no arg) | `GET /v2/apps` |
| List versions for one app | `mcp__mittwald__mittwald_app_versions` with `app="wordpress"` | `mw app versions <name>` | `GET /v2/apps/{appId}/versions` |
| Inspect a specific version (required user-inputs, recommended flag) | (use CLI / API) | `mw app version-info <versionId>` | `GET /v2/app-versions/{versionId}` |
| List **installed** apps in a project | `mcp__mittwald__mittwald_app_list` with `projectId` | `mw app list -p <projectId>` | `GET /v2/projects/{projectId}/app-installations` |

> **Don't confuse `app_list` with the catalog.** `app_list` is project-scoped and returns *installations*, not the catalog. The catalog comes from `app_versions`. Mixing the two is Pitfall #18.

## Two installation paths in the CLI

The `mw app` topic splits into:

- **`mw app install <name>`** — for *catalog-managed* apps where Mittwald owns the runtime and update path. Today: `contao`, `joomla`, `matomo`, `nextcloud`, `shopware5`, `shopware6`, `typo3`, `wordpress`. (Other catalog entries with their own install subcommand will appear here as Mittwald adds them — don't assume this list is complete; re-check `mw app install --help`.)
- **`mw app create <runtime>`** — for *self-managed runtime* apps where you own the code. Today: `node`, `php`, `php-worker`, `python`, `static`.

In the API, both paths exist as different endpoints under the project's app-installations tree. The OpenAPI spec is authoritative; consult <https://api.mittwald.de/v2/openapi.json> when wiring scripts.

> **MCP gap.** As of this writing the Mittwald MCP server exposes `app_list`, `app_get`, `app_versions`, `app_copy`, `app_upgrade`, `app_uninstall`, `app_update`, `app_list_upgrade_candidates` — but **no `app_install` or `app_create`**. To provision a Managed App or runtime app, fall back to CLI (`mw app install/create …`) or API. Re-check this assumption when MCP gains those tools.

## Heuristic: tag in the catalog tells you the kind

The catalog list (`GET /v2/apps`) returns objects shaped roughly as:

```json
{ "id": "<uuid>", "name": "WordPress", "tags": ["CMS"] }
{ "id": "<uuid>", "name": "PHP",       "tags": ["Eigene App"] }
```

The `"Eigene App"` tag is the runtime-app marker. Workflow:

1. Query the catalog.
2. Split entries by tag: `"Eigene App"` → runtime/self-managed bucket; everything else → Managed-App bucket.
3. Match the source against both buckets (see routing matrix below).
4. If multiple matches, present them to the operator and let them pick.

## Routing matrix — source shape → target app type

This is heuristics, not a contract. Confirm with the operator before acting.

| Source shape | Target app type | Why |
|---|---|---|
| Vanilla WordPress / Joomla / TYPO3 / Contao / Drupal / Nextcloud / Matomo / Shopware install — minimal framework-level customization | **Managed App** (matching catalog entry) | Mittwald handles runtime, patches, often DB. Operator only ships content + plugins. |
| Custom PHP application (Laravel, Symfony, custom framework) with `composer.json` | **PHP runtime app** (`mw app create php`) | Mittwald supplies PHP runtime; operator deploys their code. |
| Supervisor-style background workers tied to a PHP app (Laravel queue workers, Symfony Messenger, custom long-running PHP processes) | **PHP-Worker app** (`mw app create php-worker`), paired with the PHP app above | Native worker semantics; one PHP app + N worker apps is the recommended shape. Avoid putting workers in the PHP app's web container. |
| Node.js application (Express, Next.js standalone, NestJS, …) | **Node.js runtime app** (`mw app create node`) | Mittwald supplies Node runtime; operator deploys their code. |
| Python application (Django, Flask, FastAPI, …) | **Python runtime app** (`mw app create python`) | Same model as PHP/Node. |
| Static site (Hugo, Astro static output, plain HTML/CSS) | **Static Files app** (`mw app create static`) | Lightest weight; no runtime. |
| Workload outside any of the above, OR requires non-standard system packages, multiple coupled services with custom orchestration, exotic runtimes, non-standard databases | **Container Stack** (Compose-shaped YAML via `mw stack deploy`) | The escape hatch. You own the runtime; full Compose semantics. |
| Workload that already runs as a Managed App on **another** mStudio project | Check `app_copy` (CLI: `mw app copy`) before installing fresh | Avoids re-doing the install dance. |

### When **not** to pick a Managed App / runtime app, even if it looks like a match

- Source depends on a **specific PHP / Node / Python version** that isn't in `mw app versions <runtime>`. Either upgrade-the-source first or fall back to Container Stack.
- Source has **custom system packages** baked into its image (system-level libs the runtime apps don't ship). → Container Stack.
- Source uses **runtime-level features Mittwald's runtime app doesn't expose** (e.g. specific PHP extensions, FFI, sidecar processes that aren't worker-shaped). → Container Stack.
- Source is **highly coupled to multiple long-lived services** in one deployment unit (app + cache + DB + a message broker, all started together with shared lifecycle). → Container Stack.

## Version-compat diff

Once the candidate app type is chosen, **diff the source version against what Mittwald offers**. The skill must surface mismatches *before* the operator commits to a target shape.

Procedure:

1. Read the source's version from the Discovery inventory (e.g. "WordPress 6.4.3", "PHP 7.4.33").
2. Query `mw app versions <name>` (or the MCP/API equivalent) for the supported list.
3. Three outcomes:
   - **Exact match available** → use it. Note whether it's `recommended` (the API marks one version per app as recommended).
   - **Higher version available, source's version is not** → flag as an **upgrade-required** step. Source must be updated to a supported version before/during migration. This is not a blocker but the operator needs to know.
   - **No compatible version** (source is older than the lowest supported, or Mittwald only offers a major version that's a breaking change away) → flag as a **blocker**. Either operator upgrades the source first, or the workload falls back to Container Stack with a custom image.

Surface the diff to the operator as a small table:

```
Source: WordPress 6.4.3
Mittwald offers: 6.0.x, 6.1.x, 6.2.x, ..., 6.6.x (recommended: 6.6.2)
Result: upgrade-required — pick a target version
```

## Quick check: catalog reachable?

Before declaring "no Managed App fits", confirm the catalog query actually worked. Token without `apps:read` scope can return a partial list silently. Sanity check:

```bash
# CLI
mw app versions | head -5     # expect non-empty, multiple app names
# API
curl -sS -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  https://api.mittwald.de/v2/apps | jq 'length'  # expect a small positive integer (~15–25)
```

If the list is empty, the surface or token scope is the problem, not the catalog. Fix that before recommending a target shape.

## External resources

- **Developer portal**: <https://developer.mittwald.de/> — SDKs, additional tooling, runtime-app docs (PHP / Node / Python / Static / PHP-Worker specifics, build hooks, etc.).
- **API tokens**: <https://studio.mittwald.de/app/profile/api-tokens> — required for CLI (`MITTWALD_API_TOKEN`) and API surfaces.
- **OpenAPI spec**: <https://api.mittwald.de/v2/openapi.json> — authoritative shape for `/v2/apps`, `/v2/apps/{id}/versions`, `/v2/app-versions/{id}`, and the project-scoped install endpoints.

## Pitfalls

- **#1** — IDs again: `appId`, `versionId`, `installationId`, `projectId` are all distinct UUIDs.
- **#18** — Hardcoded catalog assumption / `app_list` (installed) vs `app_versions` (catalog) mix-up.
