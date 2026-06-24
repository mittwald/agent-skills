# AGENTS.md

**OpenAI Codex / agent instruction shim for agent-skills**

This file provides agent instructions for OpenAI Codex and other AI assistants that load instructions from `AGENTS.md` rather than skill directories.

There are two ways an agent interacts with this repo:

- **Using the skills** — guiding a migration or deployment. Start at [Skills Available](#skills-available).
- **Working on the repo** — editing skills, playbooks, references, or docs. Read [Working on This Repository](#working-on-this-repository-quality-gates) first.

---

## Working on This Repository (Quality Gates)

If you are **editing this repository** (not just using the skills), note that it is
pure markdown and its quality is enforced by CI (`.github/workflows/ci.yml`). The
same three checks run on every pull request.

**Before creating any commit, run all three locally and make sure they pass.** A
green local run means a green PR.

```bash
# 1. Markdown: auto-fix mechanical issues, then verify the result is clean.
#    Config: .markdownlint-cli2.jsonc
npx markdownlint-cli2 --fix "**/*.md"   # rewrites files in place
npx markdownlint-cli2 "**/*.md"         # must report 0 errors

# 2. Internal links resolve. Config: lychee.toml
#    Needs lychee (https://github.com/lycheeverse/lychee). No local install? Use Docker:
#    docker run --rm -v "$PWD:/input" -w /input lycheeverse/lychee --offline --no-progress .
lychee --offline --no-progress .         # must report 0 errors

# 3. SKILL.md conventions: frontmatter present, name matches directory, < 200 lines.
bash scripts/validate-skills.sh
```

Rules of thumb:

- **Fix failures before committing** — never commit with a failing gate.
- **Keep mechanical formatting in its own commit.** When `--fix` reformats files,
  commit that reformat separately (e.g. `style: apply markdownlint auto-fixes`) from
  content changes, so the substantive diff stays readable.
- **External URLs are not checked per-commit** — a weekly workflow
  (`.github/workflows/external-links.yml`) checks them and opens an issue on failure.
- Use **conventional commits** (`feat:`, `fix:`, `docs:`, `ci:`, `style:` …). See
  [DEVELOPING.md](DEVELOPING.md) for the full contributor guide.

---

## Skills Available

This repository contains two skills for working with mittwald mStudio:

1. **mittwald-migrate** - Phase-by-phase migration workflows
2. **mittwald-zerodeploy** - Zero-config deployment with Railpack

---

## mittwald-migrate

**Purpose**: Guide conversational, phase-by-phase migration of arbitrary workloads to mittwald mStudio.

**Triggers**:

- "migrate to Mittwald"
- "Umzug nach Mittwald"
- "move to mStudio"
- "container hosting on Mittwald"
- References to "stack_deploy"

**Workflow**: Discovery → Plan → Provision → Migrate → Verify → Cutover

**When activated**:

1. Load `skills/mittwald-migrate/SKILL.md` to understand the workflow
2. Follow playbooks in `skills/mittwald-migrate/playbooks/` phase by phase
3. Reference `skills/mittwald-migrate/references/` for background knowledge
4. Confirm with user before any destructive action

**Key playbooks**:

- `playbooks/discover-source.md` - Map source environment
- `playbooks/provision-target.md` - Create mStudio project/app/database
- `playbooks/migrate-files.md` - Transfer files via rsync/scp
- `playbooks/migrate-mysql.md` - Dump and restore MySQL
- `playbooks/migrate-postgres.md` - Dump and restore PostgreSQL
- `playbooks/cutover-dns.md` - Switch DNS to new host
- `playbooks/rollback.md` - Revert if needed

**Key references**:

- `references/mittwald-surfaces.md` - How to talk to mStudio (MCP/CLI/API)
- `references/ssh-modes.md` - SSH access patterns
- `references/pitfalls.md` - 25+ known migration traps
- `references/app-catalog.md` - Available app templates
- `references/database-engines.md` - Supported database types

---

## mittwald-zerodeploy

**Purpose**: Zero-config deployment to mStudio container hosting using Railpack.

**Triggers**:

- "deploy to mittwald"
- "help me deploy"
- "set up mittwald deployment"
- "GitHub Actions for mittwald"
- "my mittwald deployment is failing"

**Workflow**: Provision → Local CLI Deploy → GitHub Actions → Verify

**When activated**:

1. Load `skills/mittwald-zerodeploy/SKILL.md` to understand the workflow
2. Follow numbered playbooks in `skills/mittwald-zerodeploy/playbooks/`
3. Reference `skills/mittwald-zerodeploy/references/` for troubleshooting
4. Avoid the 3 critical gotchas (Dockerfiles, ports, exotic projects)

**Key playbooks**:

- `playbooks/01-provision-target.md` - Verify mStudio setup
- `playbooks/02-cli-deploy-local.md` - Test with `mw experimental deploy`
- `playbooks/03-setup-github-action.md` - Automated CI/CD
- `playbooks/04-troubleshoot-deployment.md` - Debug failures
- `playbooks/05-verify.md` - Post-deployment checks

**Key references**:

- `references/pitfalls.md` - 3 critical deployment gotchas
- `references/railpack-overview.md` - How Railpack auto-detection works
- `references/port-configuration.md` - Fix port mismatches
- `references/secrets-management.md` - Handle environment variables
- `references/when-to-escalate.md` - When to hand off to DevOps

---

## Connecting to Mittwald

All skills require **at least one** way to communicate with mittwald mStudio:

### Option 1: MCP Server

- Best if Codex session has mittwald MCP server connected
- Skills call `mcp__mittwald__mittwald_*` tools directly
- Token stored in MCP config

### Option 2: `mw` CLI

- Best for terminal workflows
- Install: `brew tap mittwald/cli && brew install mw` or `npm install -g @mittwald/cli`
- Authenticate: `mw login token`
- Token stored at `~/.config/mw/token`

### Option 3: HTTP API

- Best for scripts
- Set: `export MITTWALD_API_TOKEN=<token>`
- Or use `example.env` template in this repo

**API Token**: Obtain from <https://studio.mittwald.de/app/profile/api-tokens> with **`api_write`** scope.

---

## Execution Pattern

When a skill is triggered:

1. **Load SKILL.md** from the appropriate skill directory
2. **Understand the workflow** - what phases/steps are involved
3. **Load the relevant playbook** for the current phase
4. **Execute step-by-step** - follow playbook instructions
5. **Load references on-demand** when playbooks mention them
6. **Confirm before destructive actions** - always ask user first
7. **Handle errors gracefully** - check pitfalls.md, offer recovery steps
8. **Advance to next phase** - load next playbook when current is complete

---

## Path Resolution

All playbook and reference paths are relative to the skill directory:

- `skills/mittwald-migrate/playbooks/migrate-mysql.md`
- `skills/mittwald-zerodeploy/references/pitfalls.md`

If this `AGENTS.md` is at the project root, and skills are in `skills/`, use relative paths:

```
./skills/mittwald-migrate/SKILL.md
./skills/mittwald-migrate/playbooks/discover-source.md
./skills/mittwald-zerodeploy/SKILL.md
./skills/mittwald-zerodeploy/playbooks/01-provision-target.md
```

If the skills directory is elsewhere, adjust paths accordingly.

---

## Design Principles

1. **Skills are pure markdown** - no code, no APIs, agent-agnostic
2. **Playbooks are executable** - step-by-step, concrete actions
3. **References are background** - context, explanations, troubleshooting
4. **SKILL.md is an index** - workflow overview, links to playbooks/references
5. **User confirmation** - never make destructive changes without asking

---

## Troubleshooting

If skills don't activate:

1. Verify paths: Can you read `skills/mittwald-migrate/SKILL.md`?
2. Check triggers: Does user input match trigger phrases?
3. Load manually: Explicitly load the SKILL.md and follow from there

Common issues:

- **403 API errors**: Token has `api_read` only, needs `api_write`
- **SSH errors**: Public key not registered at <https://studio.mittwald.de/app/profile/ssh-keys>
- **502 after deployment**: Port mismatch, check logs and reconfigure ingress

Full troubleshooting:

- Migrate: `skills/mittwald-migrate/references/pitfalls.md`
- Deploy: `skills/mittwald-zerodeploy/references/pitfalls.md`

---

## Resources

- **Main README**: `README.md` in this repository
- **Contribution guide**: `DEVELOPING.md`
- **mittwald Developer Docs**: <https://developer.mittwald.de>
- **mittwald CLI**: <https://github.com/mittwald/cli>
- **Railpack**: <https://railpack.com>

---

## License

MIT License - See `LICENSE` for details.
