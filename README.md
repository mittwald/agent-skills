# agent-skills

**AI agent skills for mittwald mStudio** - Conversational guidance for migrations and zero-config deployments.

This repository contains two skills for working with mittwald mStudio:

1. **mittwald-migrate** - Phase-by-phase migration of workloads to mStudio
2. **mittwald-zerodeploy-skill** - Zero-config deployment using Railpack

---

## What's in this repository

### mittwald-migrate

Guides conversational, phase-by-phase migration of arbitrary workloads **to mittwald mStudio**. The source can be anything — Kubernetes, Docker Compose, a VPS, another hoster, another mStudio project.

**Workflow**: Discovery → Plan → Provision → Migrate → Verify → Cutover

**Triggers**: "migrate to Mittwald", "Umzug nach Mittwald", "move to mStudio"

**Location**: [`skills/mittwald-migrate/`](skills/mittwald-migrate/)

### mittwald-zerodeploy-skill

Zero-config deployment to mStudio container hosting using Railpack auto-detection. No Dockerfile needed.

**Workflow**: Provision → Local CLI Deploy → GitHub Actions → Verify

**Triggers**: "deploy to mittwald", "help me deploy", "set up mittwald deployment"

**Location**: [`skills/mittwald-zerodeploy-skill/`](skills/mittwald-zerodeploy-skill/)

---

## Quick Start

### 1. Prerequisites

Before using either skill:
- ✅ Active mittwald mStudio account
- ✅ API token with **`api_write`** role from <https://studio.mittwald.de/app/profile/api-tokens>
- ✅ mittwald CLI installed ([install guide](https://developer.mittwald.de/docs/v2/cli/))

### 2. Install the skills

**For Claude Code** (recommended) — use the native plugin marketplace:
```bash
/plugin marketplace add mittwald/agent-skills
/plugin install mittwald-migrate@agent-skills
/plugin install mittwald-zerodeploy-skill@agent-skills
```

**For any other AI assistant** — use the [`skills`](https://www.npmjs.com/package/skills) CLI:
```bash
npx skills add mittwald/agent-skills
```

This installs the skills into the location your agent expects (e.g. VS Code Copilot, Cursor, and others).

**Manual install** (fallback) — clone the repository into your agent's skills directory:
```bash
# VS Code Copilot — personal skills
git clone https://github.com/mittwald/agent-skills.git ~/.agents/skills/mittwald-skills

# Claude Code
git clone https://github.com/mittwald/agent-skills.git ~/.claude/skills/mittwald-skills
```
Check your agent's documentation for the correct skill installation path.

### 3. Trigger the skills

**For migrations**:
> "I want to migrate my WordPress site from Hetzner to Mittwald."

**For deployments**:
> "Help me deploy my Express app to mittwald"

The AI assistant will load the appropriate skill and guide you through the workflow.

---

## Connecting to Mittwald

Both skills need **at least one** way to talk to mStudio. You don't have to set up all three — pick whichever fits.

### Option 1 — MCP server (best if your AI assistant supports it)

The Mittwald MCP server runs inside your AI session; the skills call its `mcp__mittwald__mittwald_*` tools directly. Setup instructions: **[AI-assisted development guide](https://developer.mittwald.de/docs/v2/platform/development/ai-coding/)**.

### Option 2 — `mw` CLI (best for terminal workflows)

Install:
```bash
brew tap mittwald/cli && brew install mw      # macOS
# or: npm install -g @mittwald/cli            # any OS, Node ≥ 20.7
```

Authenticate:
```bash
mw login token          # paste your api_write token
mw user get             # verify it works
```

### Option 3 — HTTP API (for scripts)

Set environment variable:
```bash
export MITTWALD_API_TOKEN=<your-api_write-token>
curl -H "Authorization: Bearer $MITTWALD_API_TOKEN" https://api.mittwald.de/v2/users/self
```

Or use [`example.env`](example.env) as a template.

---

## SSH Access (for migrations)

The **mittwald-migrate** skill creates SSH users on demand when needed. You usually don't need to configure SSH manually.

If you want to SSH in yourself:
- Register your public key at <https://studio.mittwald.de/app/profile/ssh-keys>
- Your SSH identity is your studio account's email

Details: [`skills/mittwald-migrate/references/ssh-modes.md`](skills/mittwald-migrate/references/ssh-modes.md)

---

## Skill Structure

```
agent-skills/
├── skills/
│   ├── mittwald-migrate/          # Migration skill
│   │   ├── SKILL.md               # Workflow index
│   │   ├── playbooks/             # Phase-by-phase guides
│   │   │   ├── discover-source.md
│   │   │   ├── provision-target.md
│   │   │   ├── migrate-files.md
│   │   │   ├── migrate-mysql.md
│   │   │   ├── migrate-postgres.md
│   │   │   ├── cutover-dns.md
│   │   │   ├── rollback.md
│   │   │   └── contribute-learnings.md
│   │   └── references/            # Background knowledge
│   │       ├── mittwald-surfaces.md
│   │       ├── mittwald-mcp-tools.md
│   │       ├── ssh-modes.md
│   │       ├── app-catalog.md
│   │       ├── database-engines.md
│   │       ├── cms-quirks.md
│   │       ├── pitfalls.md
│   │       ├── stateful-container-restore.md
│   │       └── compose-templates/
│   │
│   └── mittwald-zerodeploy-skill/  # Deployment skill
│       ├── SKILL.md                # Workflow index
│       ├── playbooks/              # Step-by-step guides
│       │   ├── 01-provision-target.md
│       │   ├── 02-cli-deploy-local.md
│       │   ├── 03-setup-github-action.md
│       │   ├── 04-troubleshoot-deployment.md
│       │   └── 05-verify.md
│       └── references/             # Background knowledge
│           ├── pitfalls.md
│           ├── railpack-overview.md
│           ├── secrets-management.md
│           ├── port-configuration.md
│           └── when-to-escalate.md
│
├── README.md                       # This file
├── DEVELOPING.md                   # Contribution guidelines
├── AGENTS.md                       # OpenAI Codex support
├── LICENSE                         # MIT license
└── example.env                     # API token template
```

---

## Troubleshooting

### Common Issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `403 PermissionDenied` on any API/CLI call | Token has `api_read` only | Re-issue with `api_write` at <https://studio.mittwald.de/app/profile/api-tokens> |
| `Permission denied (publickey)` on SSH | Public key not registered | Register at <https://studio.mittwald.de/app/profile/ssh-keys> or let skill create ssh-user |
| `mw: command not found` | CLI not installed | `brew tap mittwald/cli && brew install mw` |
| `mw user get` says LOGIN REQUIRED | Not authenticated | `mw login token` or `export MITTWALD_API_TOKEN=...` |
| Skill doesn't activate on trigger | AI assistant didn't rescan | Restart your AI assistant |
| Deployment succeeds but 502 errors | Port mismatch | Check logs, reconfigure ingress in mStudio UI |
| Container crash-loops on first start | Permission issue on bind-mount | `chmod 777` the path before deploy |

### Skill-Specific Troubleshooting

- **mittwald-migrate**: See [`skills/mittwald-migrate/references/pitfalls.md`](skills/mittwald-migrate/references/pitfalls.md) for 25+ migration-specific issues
- **mittwald-zerodeploy-skill**: See [`skills/mittwald-zerodeploy-skill/references/pitfalls.md`](skills/mittwald-zerodeploy-skill/references/pitfalls.md) for the 3 critical deployment gotchas

---

## Usage Examples

### Migration Example

**User**: "I want to migrate my WordPress site from Hetzner to Mittwald"

**AI Assistant** (using mittwald-migrate):
1. Loads discovery playbook
2. Asks about source environment (Hetzner VPS details)
3. Plans target mStudio structure
4. Provisions project, app, database
5. Migrates files via rsync/scp
6. Migrates MySQL database
7. Verifies everything works
8. Guides DNS cutover

### Deployment Example

**User**: "Help me deploy my Express app to mittwald"

**AI Assistant** (using mittwald-zerodeploy-skill):
1. Verifies mStudio setup
2. Tests deployment locally with `mw experimental deploy`
3. Sets up GitHub Actions workflow
4. Guides through secrets configuration
5. Verifies deployment

---

## Testing the Skills

### Dry Run (migrate)

For a non-destructive test:

> "Walk me through Discovery for a fictitious WordPress source. We're not provisioning anything yet."

The skill will exercise API checks without making changes.

---

## OpenAI Codex Support

If you use OpenAI Codex: place [`AGENTS.md`](AGENTS.md) at your project root. It references the same playbooks via relative paths.

---

## Contributing

See [DEVELOPING.md](DEVELOPING.md) for:
- Repository structure and design rationale
- Adding new playbooks or references
- Testing skill changes
- Contribution guidelines

---

## Resources

### Official Documentation
- **mittwald mStudio**: https://studio.mittwald.de
- **mittwald Developer Docs**: https://developer.mittwald.de
- **mittwald CLI**: https://github.com/mittwald/cli
- **Container Deployment Guide**: https://developer.mittwald.de/docs/v2/guides/deployment/container-actions/
- **AI-assisted Development**: https://developer.mittwald.de/docs/v2/platform/development/ai-coding/
- **Railpack**: https://railpack.com/getting-started

### Support
- **mittwald Support**: Ticket system at https://studio.mittwald.de (login required)
- **GitHub Issues**: [Report skill issues here](https://github.com/mittwald/agent-skills/issues)

---

## Compatibility

These skills work with any AI coding assistant that supports:
- ✅ Reading markdown files
- ✅ Loading skill definitions from a directory
- ✅ Following structured playbook workflows

---

## License

MIT License - See [LICENSE](LICENSE) for details.

---

Created with love for the mittwald developer community to simplify migrations and deployments.
