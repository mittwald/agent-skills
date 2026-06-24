# Playbook: Cutover (DNS swap)

**Goal:** flip public traffic from the source to the Mittwald stack with zero ambiguity about state. Entry condition: Verify phase passed against `<shortId>.project.space`.

This is the most-visible step. Operator confirmation gates here are non-negotiable.

## 1. Pre-cutover checklist (gate)

Walk through this with the operator and get explicit confirmation:

- [ ] Smoke test on `<shortId>.project.space` passes — golden path, login, write+read.
- [ ] Row counts match source ↔ target (Pitfall #13).
- [ ] File counts match source ↔ target.
- [ ] No restart-loop / error spam in `container_logs` for the past 15 min.
- [ ] Background workers / queues drained on source.
- [ ] Backup taken on Mittwald side: `mcp__mittwald__mittwald_backup_create` (rollback point).
- [ ] **Operator can identify the rollback step** (see `rollback.md`).
- [ ] DNS TTL lowered ≥ TTL minutes ago (next section).
- [ ] **CMS URL-rewrite done in DB**, not just code config. For WordPress: `wp search-replace 'https://old' 'https://new' --skip-columns=guid`. For TYPO3 v9+: update `config.yaml` `base:` for each site. For Shopware: update `s_core_shops.host` (SW5) / `sales_channel_domain.url` (SW6). Full per-CMS locations in [`../references/cms-quirks.md`](../references/cms-quirks.md).
- [ ] **CMS-specific plugin/extension config reviewed** for source-environment lockouts before flipping DNS — WordPress especially (Pitfall #23: WP-Hide-Login whitelist, Wordfence paths, cache plugins).

If any item is unchecked, **do not proceed**.

## 2. TTL drop ahead of cutover

Long DNS TTLs (3600s+ is typical) mean stale resolvers point at the old IP for up to an hour after the change. Drop TTLs to **60-300 seconds** at least one previous-TTL-cycle before the cutover window.

Example: current TTL is 3600s. At T-2h, change TTL to 60s. By T-0 (cutover), all caches have ≤60s of staleness.

Mittwald's own DNS zones:

```text
mcp__mittwald__mittwald_domain_dnszone_get
mcp__mittwald__mittwald_domain_dnszone_update     # if Mittwald is also authoritative for the zone
```

If DNS is hosted at the operator's registrar / Cloudflare / Route53 — the operator changes it there. The MCP server cannot reach external DNS providers.

## 3. Final source freeze

Stop the source app **and** any worker / queue / cron processes:

| Source | Action |
|---|---|
| Kubernetes | `kubectl -n <ns> scale deploy/<app> deploy/<worker> --replicas=0` |
| Compose | `docker compose stop` |
| systemd | `systemctl stop <app>.service <worker>.service` |

Do **not** delete anything. The source is your rollback target (Pitfall #15).

If a writeable DB is still up, that's fine — but stop anything that writes to it.

## 4. Last incremental sync (if applicable)

If files were transferred with `rsync` (resumable), run one final delta pass while the source is quiesced:

```bash
rsync -aHv --delete-after -e ssh /srv/myapp/uploads/ "$TGT_PROJ_SSH:/files/myapp/uploads/"
```

For DB, take a fresh dump from the now-frozen source and restore it — repeat the relevant migrate-DB playbook from the dump step onward.

This is the **point of no easy return**: after this, source data and target data diverge if the source comes back up.

## 5. Flip DNS

The new target is the **IP of the Mittwald virtualhost**. Find it:

```text
mcp__mittwald__mittwald_domain_virtualhost_list
# look up the entry for <hostname>; the ipv4 / ipv6 fields are what you set as A / AAAA records.
```

The operator changes the records at their authoritative DNS provider. Three common scenarios:

### 5a. Direct A/AAAA record (no proxy in front)

Change A and AAAA records to Mittwald's virtualhost IPs. Done.

Watch propagation:

```bash
dig +short A foo.example.com @1.1.1.1
dig +short A foo.example.com @8.8.8.8
```

Mittwald requests Let's Encrypt automatically once the hostname resolves to its IP. Watch:

```text
mcp__mittwald__mittwald_domain_virtualhost_get      # check ssl/tls status field
```

### 5b. Cloudflare in front (proxied)

Pitfall #10. Decide before this step which fix applies:

- **Option A**: Set Cloudflare to "DNS only" (grey cloud) for the hostname → flip A/AAAA to Mittwald → wait for LE cert to issue on Mittwald → switch back to "Proxied" (orange cloud).
- **Option B**: Upload a Cloudflare Origin Certificate to Mittwald via `mcp__mittwald__mittwald_certificate_request` (custom cert mode) **before** flipping DNS. Then flip DNS with proxy still on; public TLS terminates at Cloudflare.
- **Option C** (Cloudflare SSL mode "Full", not "Full strict"): accept Mittwald self-signed. Cloudflare won't validate the upstream cert. Document the trade-off; this is not appropriate for many compliance contexts.

### 5c. Other CDN (Bunny, Fastly, …)

Equivalent to Cloudflare — origin is now Mittwald. Update the origin host in the CDN config and ensure cert handling is consistent.

## 6. Post-cutover verification

For the next 30 minutes:

- Hit the **public** hostname from multiple regions / resolvers (`dig` from a few nodes; or use a third-party check).
- Watch `container_logs` for 4xx/5xx spikes.
- Watch the application's own error tracker (Sentry / equivalent), if any.
- Verify cert status: `domain_virtualhost_get` → SSL fields should reflect a valid LE cert issued in the last few minutes (or your custom cert, if 5b option B).

If anything looks wrong: see `rollback.md` for the DNS-revert procedure.

## 7. Soft decommission of the source

Do **not** decommission yet. Recommended window:

- **T+24h**: spot-check error rates, user complaints. If healthy, raise TTLs back to a sane value (300s → 3600s).
- **T+7d**: confirm with operator that source can be archived. Backups stay; running services stop.
- **T+14d-30d**: actual decommission. Source-side backup retention extended past this point per operator's RPO policy.

Track this as a calendar item with the operator. The skill stops here; don't auto-delete source.

## 8. Confirmation gate before DNS change

Before instructing the operator to flip DNS, summarize:

```
About to cutover <hostname> to Mittwald stack <name> in project <shortId>.
  - Source: <description>, currently running but writes stopped.
  - Target: stack ps shows N services running, last log scan clean as of <time>.
  - Final delta sync: <none | done at HH:MM>.
  - Cloudflare strategy: <A / B / C from §5b>.
  - DNS TTL: <current TTL>. Lowered to 60s at <time>.
  - LE cert status on target: <pending | issued>.
  - Rollback plan: revert A/AAAA to <old IP>, source app re-scale to N. Estimated revert latency: TTL (~60s) + restart (~30s).
```

Ask `AskUserQuestion`: confirm cutover / hold / abort.

## Pitfalls referenced

- #10 Cloudflare ↔ Let's Encrypt
- #13 Row-count verification before DNS flip
- #15 Source stays as rollback for the agreed window
- #17 Default domain testing was already done in Verify — don't skip back to it now
- #23 WordPress plugin lockouts / Wordfence path mismatch — handle before flipping DNS, not after
