# Playbook: Contribute learnings (optional)

**Goal:** at the very end of a migration, **offer** the operator the chance to file a short, **fully sanitized** GitHub issue summarizing what happened — so the skill's runbooks and pitfalls can grow from real migrations.

**This is an opt-in offer, never a requirement.** If the operator says no (or doesn't answer), drop it silently and end the session. Never file anything without explicit approval, and never include sensitive data.

Entry condition: the migration reached a natural end (Verify passed, or Cutover done, or the operator stopped). Works equally after a rollback — a migration that *failed* is often the most useful learning.

---

## 1. The offer (gate #1)

Ask once, plainly, with `AskUserQuestion` (or the surface's equivalent):

> "Optional: I can draft a short, anonymized issue on the mittwald `agent-skills` GitHub repo summarizing this migration — what worked, what was unclear, any new trap — so the skill improves over time. **It contains no secrets or identifying details** (I'll show you the exact text first). Want me to draft it?"

Default is **no**. If declined, end here. Don't re-ask, don't nag.

---

## 2. Sanitization — the hard rules

The issue is **public**. Treat everything as if a stranger will read it (they will). Build the body from generalized facts only.

### NEVER include (hard deny — no exceptions)

- API tokens, passwords, secret keys, SSH private/public keys, `.env` contents, DB credentials, connection strings
- Project UUIDs, project short-IDs (`p-…`), app/container short-IDs (`a-…`, `c-…`), stack IDs
- Real domains / hostnames / vhost names, real IP addresses
- Email addresses, customer or organization names, person names
- Real database names, schema names, table names if they're app- or customer-specific
- Absolute filesystem paths that embed any of the above (e.g. `/home/p-ab12cd/…`)
- Exact data sizes or row counts that could fingerprint a specific customer

### Obfuscate / generalize (use placeholders)

| Real thing | Put in the issue |
|---|---|
| `shop.kunde-xyz.de` | `<domain>` or `example.com` |
| project UUID / `p-ab12cd` | `<projectId>` / `p-XXXXX` |
| `a-mdrqq5` / `c-b24c3b` | `a-XXXXX` / `c-XXXXX` |
| `203.0.113.7` | `<ip>` |
| `max@kunde-xyz.de` | `<email>` |
| "WeClapp-Prod" / customer name | `<org>` / omit |
| exact size `42.7 GB` | a bucket: `<1 GB` / `1–10 GB` / `10–50 GB` / `50 GB+` |
| `/home/p-ab12cd/html` | `/home/<p-shortId>/html` |

### Safe to include (this is the useful signal)

- Source **category**: Kubernetes / Docker Compose / VPS / another hoster / another mStudio project
- Target **shape**: Managed App `<name>` / runtime app `<type>` / Container Stack
- Generic app/CMS + **major** version only: "WordPress 6.x", "TYPO3 12 (Composer)", "Shopware 6"
- DB **engine + major version**, managed-vs-container: "MySQL 8.4 (managed)", "Postgres 15 (container)"
- Which **Pitfall #N**s were hit, and a one-line note on how each manifested (sanitized)
- What was **unclear or missing** in the skill; any **new trap** discovered
- Rough phase durations and a data-size **bucket**
- Surfaces used (MCP / CLI / API)

When unsure whether something is safe → **leave it out**. Generic-but-useful beats specific-but-risky.

---

## 3. Draft the issue body

Fill this template. Keep it to facts you can state generically. Leave a section out if there's nothing safe to say.

```markdown
<!-- mittwald-migrate learnings — auto-drafted, operator-reviewed, sanitized -->

### Migration summary (sanitized)
- Source: <category>
- Target shape: <Managed App <name> | runtime app <type> | Container Stack>
- App / CMS: <generic + major version, or n/a>
- Databases: <engine + major version, managed|container; or n/a>
- Data size bucket: <<1 GB | 1–10 GB | 10–50 GB | 50 GB+>
- Surfaces used: <MCP | CLI | API>

### Pitfalls encountered
- #<N> — <one sanitized line on how it showed up>
- (none / or list)

### What was unclear or missing in the skill
- <free text, sanitized — placeholders only>

### Suggested additions
- New pitfall? <symptom → why → fix sketch>
- Runbook gap? <which playbook + which step was thin or wrong>

### Rough timing
- <phase>: ~<minutes>

---
- [x] I confirm this summary contains **no secrets and no identifying details**.
```

---

## 4. Show it and confirm (gate #2)

**Render the complete issue body to the operator verbatim** and ask them to:

- read it,
- redact or edit anything they want,
- explicitly approve creation.

> "Here's the exact issue I'd file (nothing else is sent). Create it, edit it first, or skip?"

Do not proceed without an explicit "create". If the operator edits, re-show the final version.

---

## 5. Create it

Target the marketplace repo (`mittwald/agent-skills`) with the `migration-learnings` label so maintainers can find it.

**Preferred — `gh` CLI** (if available and the operator is authenticated):

```bash
gh issue create \
  --repo mittwald/agent-skills \
  --label migration-learnings \
  --title "Migration learnings: <source-category> → <target-shape>" \
  --body-file <(cat <<'BODY'
<the approved, sanitized body from step 3>
BODY
)
```

If the `migration-learnings` label doesn't exist on the operator's side, drop `--label` (a maintainer labels it later) — don't let a missing label block the contribution.

**Fallback — no `gh` / no access:** print the title + body in a fenced block and tell the operator they can paste it at
`https://github.com/mittwald/agent-skills/issues/new` (label `migration-learnings` if they can). Filing on a public repo only needs a GitHub account.

After creation, share the issue URL (if `gh` returned one) and thank them. Done.

---

## 6. Read-back (maintainer side — not run during a migration)

These issues are harvested separately to grow the skill. See [`../../../DEVELOPING.md`](../../../DEVELOPING.md) §"Maintenance" → "Harvesting migration-learnings issues". In short: a maintainer reads `migration-learnings`-labelled issues, turns confirmed new traps into appended pitfalls and runbook gaps into playbook edits, then closes the issue referencing the commit.

---

## Pitfalls referenced in this phase

- None directly. This is a post-migration contribution step. Its one hard rule — **no sensitive data, obfuscate everything** — is enforced inline above, not via a pitfall entry.
