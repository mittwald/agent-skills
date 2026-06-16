# CMS-specific quirks — where to look, what to fix

Read this when Discovery identifies the source as one of the common CMS:
WordPress, TYPO3 (symlink-based or Composer-based), Shopware 5, or Shopware 6.

Each section answers the same recurring questions:

- **Where's the config file?** (DB credentials, URLs, debug flags)
- **Where's the URL stored?** (base URL / siteurl — both code and DB locations)
- **What's the backend URL?** (smoke-test target on `<shortId>.project.space`)
- **How do I read the version?** (feeds the version-compat diff in [`app-catalog.md`](app-catalog.md))
- **Where are caches/logs?** (for post-migrate clearing)
- **What's the CLI?** (faster than DB surgery for routine operations)
- **What plugins/extensions trip migrations?** (cross-references to pitfalls)

Source: customer-service cheatsheet from Mittwald support. Treat as starting points — actual file paths can drift across releases; verify via the live install during Discovery.

> **PHP runtime config note.** Every CMS in this file is PHP-based. php.ini overrides go in one of two places (don't edit the main php.ini): a dedicated drop-in under `/home/<p-shortId>/.config/php/php.d/*.ini` (project-wide, via Project-Host-SSH; the only place for `extension=…` and other `PHP_INI_SYSTEM` directives), or a `.user.ini` in the app directory (travels with the app code; `PHP_INI_PERDIR`/`PHP_INI_USER` directives only, cached for `user_ini.cache_ttl` seconds). Capture the source's `memory_limit`, `upload_max_filesize`, `post_max_size`, `max_execution_time`, `date.timezone`, `opcache.*`, and custom extensions in Discovery; replicate them at Provision. Full description: [`../playbooks/provision-target.md`](../playbooks/provision-target.md) §3a "PHP runtime config".  
> Not to be confused with **Wordfence's `user.ini`** (no leading dot) — that's a WAF file, not a PHP config (Pitfall #23).

---

## WordPress

### Quick ID

- `wp-config.php` at the install root
- `wp-content/` directory with `plugins/`, `themes/`, `uploads/`
- DB tables prefixed `wp_` (default; check `$table_prefix` in `wp-config.php` — sites with security-hardening rename this)

### Config file

`wp-config.php` (install root). Holds DB credentials, secret keys, optionally hardcoded URLs.

### URL configuration

Two sources of truth — they can disagree. Reconcile before migration:

| Where | What | How |
|---|---|---|
| DB `wp_options` table | `siteurl` and `home` rows | `SELECT option_name, option_value FROM wp_options WHERE option_name IN ('siteurl','home');` |
| `wp-config.php` | `WP_SITEURL` and `WP_HOME` constants | `define('WP_SITEURL', 'https://example.com');` |

If both are set, the `wp-config.php` constants **win**. Document both sides in the Discovery rewrite map.

Hardcoded URLs are also scattered through `wp_posts.post_content`, `wp_postmeta`, theme options, etc. Tools like `wp-cli search-replace` are the standard fix at cutover:

```bash
wp search-replace 'https://old.example.com' 'https://new.example.com' --skip-columns=guid --dry-run
# then re-run without --dry-run
```

`--skip-columns=guid` is intentional — GUIDs should not change post-migration. Posts whose `guid` already points at the old domain stay as-is.

### DB credentials

`wp-config.php`: `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_CHARSET`, `DB_COLLATE`. After migration these become the in-stack hostname (`mysql` if container) or the managed-DB host (Pitfall #16).

### Backend URL

`/wp-admin` or `/wp-login.php`. Use one of these on `<shortId>.project.space/wp-admin` for the smoke test (Pitfall #17).

### Version detection

```bash
grep '^\$wp_version' wp-includes/version.php
# → $wp_version = '6.4.2';
```

This is the value to diff against `mw app versions wordpress` for the catalog self-check.

### Debug logging

For one-off Discovery troubleshooting, enable in `wp-config.php` (DO NOT leave on after migration):

```php
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
```

Logs land in `wp-content/debug.log`.

### Plugins

Live under `wp-content/plugins/<plugin-slug>/`. Disable a misbehaving one by renaming its directory (WordPress treats a missing plugin dir as "not installed"). Or use wp-cli:

```bash
wp plugin list
wp plugin deactivate <slug>
```

If wp-cli isn't on the source, install it (it's a single phar download — see <https://wp-cli.org/>).

### Plugins that complicate migrations (Pitfall #23)

- **WP-Hide-Login** — renames `/wp-admin` to a custom path and/or restricts by IP. After migration: source-IP whitelist no longer matches; the operator gets a 404 on `/wp-admin` until the plugin is reconfigured. Fix by disabling pre-cutover or updating the DB `wp_options.whl_page` / equivalent.
- **Wordfence** — hardcodes paths in `wordfence-waf.php` and/or `user.ini`. Mittwald's filesystem layout differs from typical shared-hosting paths; the WAF can fail to load. Adjust the path entries in those two files, or disable Wordfence until verified.
- **Cache plugins** (W3 Total Cache, WP Super Cache, LiteSpeed Cache, WP Rocket) — serve stale content from the old environment. Clear caches as a mandatory post-migration step, **and** invalidate any preview/edge caches outside the WP install.

### Multisite (Pitfall #24)

Check **before** sizing the migration:

```bash
grep -E "define\\(\\s*'MULTISITE'\\s*,\\s*true" wp-config.php
# also look for subdomain/subdirectory toggles
grep -E "SUBDOMAIN_INSTALL|DOMAIN_CURRENT_SITE|PATH_CURRENT_SITE" wp-config.php
```

DB-side: `wp_blogs`, `wp_site`, `wp_sitemeta` tables exist. Each site has its own `wp_<id>_*` tables. Uploads partition under `wp-content/uploads/sites/<id>/`. All of this changes downtime budget, virtualhost count, and DB sizing.

### WooCommerce

If the install runs WooCommerce, **coordinate a maintenance/landing page** at cutover. Customer orders in flight during the DNS switch can result in payments captured but orders missing — operationally messy. The maintenance page is configured at the source side; the skill doesn't handle it directly but Discovery must surface it.

---

## TYPO3 — symlink-based (legacy layout)

### Quick ID

- `typo3/` directory at the install root (the symlink to the TYPO3 core)
- `typo3conf/` directory holding site config + extensions
- No `composer.json` at the root (or one that's not the canonical install method)

### Config file

| TYPO3 version | Path |
|---|---|
| ≤ v11 | `typo3conf/LocalConfiguration.php` |
| v12+ | `typo3conf/system/settings.php` |

Both PHP arrays returning the full TYPO3 system configuration. DB creds under `DB.Connections.Default.*`.

### Base URL

| TYPO3 version | Where |
|---|---|
| ≤ v8 | Backend → Template (root page) → Setup, in TypoScript: `config.baseURL = …` |
| v9+ | `typo3conf/sites/<site-identifier>/config.yaml`, key `base:` |

For v9+, expect one `config.yaml` per site identifier (relevant for multisite — Pitfall #24).

### DB credentials

`typo3conf/LocalConfiguration.php` (or v12 path) → `DB.Connections.Default` → `dbname`, `user`, `password`, `host`.

### Backend URL

`/typo3`. Smoke test via `<shortId>.project.space/typo3`.

### Version detection

```bash
grep -E "VERSION\\s*=" typo3/sysext/core/Classes/Information/Typo3Version.php
# v9+ — varies slightly across releases
# or read from typo3conf/PackageStates.php as fallback
```

### Extensions (plugins)

`typo3conf/ext/<extension-key>/`. State managed in `typo3conf/PackageStates.php`.

### Caches

`typo3temp/` directory — safe to delete or rename to flush. DB-side: `cache_*` tables can be truncated. Or use the Install-Tool clear-cache.

---

## TYPO3 — Composer-based

### Quick ID

- `composer.json` at root with `typo3/cms-core` (or `typo3/cms-composer-installers`) as a dependency
- `vendor/` directory present
- A **`public/` subdirectory** that is the actual webroot
- No top-level `typo3/` symlink (it lives under `public/typo3/`)

### Config file

`config/system/settings.php`. Same shape as the symlinked v12 config; different location.

### Base URL

`config/sites/<site-identifier>/config.yaml`, key `base:`.

### Document root — Pitfall #22

**The webroot MUST be `<install>/public`, not `<install>`.** This is a Provision-phase concern: when wiring up the virtualhost (or the Mittwald runtime app's path), point it at `public/`. Pointing at the install root gives a 404 on everything because `index.php` lives under `public/`.

For Mittwald PHP runtime apps, this is settable per-installation. Confirm via `mw app get <installationId>` after provisioning.

### Version detection

```bash
grep -E '"typo3/cms-core"' composer.json
# or, for the actually-installed version:
jq -r '.packages[] | select(.name == "typo3/cms-core") | .version' composer.lock
```

### Everything else

Caches, extensions, multisite behavior — same as symlinked TYPO3 (see general section below).

---

## TYPO3 — general (both layouts)

### Caches

- `typo3temp/` (symlink layout) or `var/cache/` (Composer layout) — clear by deletion/rename.
- DB-side `cache_*` tables can be `TRUNCATE`d.
- Backend Install-Tool also offers a one-click clear.

### Multisite (Pitfall #24)

Check `typo3conf/sites/` (symlink) or `config/sites/` (Composer) for **multiple subdirectories** — each is a site with its own `config.yaml` and base URL. Multisite changes the migration plan (multiple virtualhosts, possibly per-site file trees, DB rows in `sys_template` and others reference site identifiers).

---

## Shopware 5

### Quick ID

- `shopware/` install root containing `config.php`
- `engine/` directory with the SW5 framework code
- DB tables like `s_articles`, `s_core_shops`, `s_user`

### Config file

`shopware/config.php` — PHP array with DB creds and a few framework switches.

### Base URL

| Where | How |
|---|---|
| Backend | Einstellungen → Grundeinstellungen → Shopeinstellungen → Shops → select language → field `Host` (leave `Präfix` empty) |
| DB | `s_core_shops` table, column `host` |

Multiple language shops mean multiple rows. Update each.

### Backend URL

`/backend`.

### CLI

`bin/console` (Symfony Console). Useful for:

- `bin/console sw:version` — version
- `bin/console sw:cache:clear` — flush cache
- `bin/console sw:plugin:list` — installed plugins
- `bin/console sw:admin:create` — create a backend user (if locked out)

### Caches / logs

- Cache: `var/cache/<env>/` (or `/var/cache/`)
- Logs: `var/log/` (or `/var/log/`)

---

## Shopware 6

### Quick ID

- `shopware/` install root containing `.env` (not `config.php`)
- `vendor/` directory (Composer-managed)
- DB tables like `product`, `order`, `sales_channel`, `sales_channel_domain`

### Config file

`shopware/.env` — DB DSN, secrets, app URL.

### Base URL

| Where | How |
|---|---|
| Backend | Verkaufskanäle → select channel → Domänen → add the domain, save |
| DB | `sales_channel_domain` table, column `url` |

One row per (sales channel × domain). For multi-channel shops, expect several entries.

### Backend URL

`/admin`.

### CLI

`bin/console` (Symfony Console). Common ones:

- `bin/console cache:clear` — flush cache
- `bin/console plugin:list` — plugins
- `bin/console user:create` — create a backend admin
- `bin/console system:config:set` — config tweaks

### Version detection

```bash
grep "shopware/core" composer.lock
# or, more reliably:
jq -r '.packages[] | select(.name == "shopware/core") | .version' composer.lock
```

### Caches / logs

- Cache: `var/cache/<env>/`
- Logs: `var/log/`

### External dependencies — check before migration

Shopware 6 commonly integrates Redis (sessions, cache, message queue) and Elasticsearch (product search). These are configured in `.env`:

- `REDIS_DSN`, `REDIS_URL`, or per-purpose vars like `SHOPWARE_CACHE_REDIS_URL`
- `SHOPWARE_ES_HOSTS`, `SHOPWARE_ES_ENABLED`

If the source uses Redis: the skill's managed-Redis path applies (see [`database-engines.md`](database-engines.md)). If Elasticsearch: it's not a managed mStudio service — containerize alongside the app stack.

---

## Cross-references

- App version detection feeds the **version-compat diff** in [`app-catalog.md`](app-catalog.md).
- URL/base-URL fields belong in the Discovery **rewrite map** ([`../playbooks/discover-source.md`](../playbooks/discover-source.md) §4).
- Cache clearing is a **post-migrate** task ([`../playbooks/migrate-files.md`](../playbooks/migrate-files.md)) and a **pre-cutover** sanity step ([`../playbooks/cutover-dns.md`](../playbooks/cutover-dns.md)).
- TYPO3 Composer document-root setting belongs in **Provision** ([`../playbooks/provision-target.md`](../playbooks/provision-target.md) §3a/§6).
- The three CMS-specific pitfalls referenced above: **#22** (TYPO3 Composer doc-root), **#23** (WP plugin traps), **#24** (multisite hidden).
