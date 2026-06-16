# mittwald-zerodeploy-skill

Zero-config deployment to mittwald mStudio container hosting using Railpack build inference.

---

## Description

This skill guides users through deploying containerized applications to mittwald mStudio **without requiring Docker knowledge**. The workflow uses Railpack to automatically detect project types and generate build plans, then deploys via the mittwald CLI or GitHub Actions.

**Perfect for**: Developers who want to deploy quickly without writing Dockerfiles.  
**Not for**: DevOps teams needing explicit container definitions (use `deploy-container-action` instead).

---

## When to use this skill

Trigger this skill when the user wants to:
- Deploy an app to mittwald without writing a Dockerfile
- Set up automated deployment with GitHub Actions to mittwald
- Troubleshoot Railpack-based deployment failures
- Transition from local CLI testing to CI/CD automation
- Fix issues with faulty AI-generated Dockerfiles
- Understand why their deployment isn't working

---

## Workflow

### Phase 1: Local Testing (CLI)

**Goal**: Validate the deployment locally before setting up automation.

1. **Load** `playbooks/01-provision-target.md`
   - Verify mStudio project exists and user has API token
   - Confirm project ID is configured or can be passed explicitly
   - Check CLI is installed and authenticated

2. **Load** `playbooks/02-cli-deploy-local.md`
   - Run `mw experimental deploy` from project root
   - Handle environment variables via `--env` or `--env-file`
   - Parse deployment output for URL and container ID
   - Verify the app is reachable

3. **Load** `playbooks/05-verify.md`
   - Check container status in mStudio web UI
   - Test HTTP endpoints and validate responses
   - Confirm environment variables are applied correctly

### Phase 2: Automation (GitHub Actions)

**Goal**: Set up continuous deployment after local testing succeeds.

4. **Load** `playbooks/03-setup-github-action.md`
   - Create `.github/workflows/zerodeploy.yml`
   - Configure GitHub secrets (`MITTWALD_API_TOKEN`, `MITTWALD_PROJECT_ID`)
   - Handle runtime secrets via workflow `.env` generation
   - Test with manual workflow dispatch

5. **Test automated deployment**
   - Trigger workflow manually
   - Monitor workflow logs for errors

6. **Load** `playbooks/05-verify.md` again
   - Confirm automated deployment produces same result as CLI

### Troubleshooting (As Needed)

**When deployment fails or behaves unexpectedly:**

- **Load** `playbooks/04-troubleshoot-deployment.md`
  - Guide user to mStudio web UI logs
  - Identify common error patterns
  - Check for faulty Dockerfiles to delete
  - Reconfigure ports if needed

**When encountering the 3 critical gotchas:**

- **Load** `references/pitfalls.md`
  - Faulty pre-existing Dockerfiles
  - Hidden port configurations
  - Exotic projects that won't work with Railpack

**When stuck after 2-3 attempts:**

- **Load** `references/when-to-escalate.md`
  - Recognize escalation triggers
  - Document errors for handoff
  - Avoid endless iteration

---

## Critical References (Load on Demand)

### Build & Detection Issues
- `references/railpack-overview.md` - when Railpack can't detect project type or build fails

### Configuration Issues
- `references/secrets-management.md` - when handling API keys, database passwords, or `.env` files
- `references/port-configuration.md` - when app won't respond on expected port or ingress issues occur

### Failure Patterns
- `references/pitfalls.md` - the 3 most common gotchas with solutions
- `references/when-to-escalate.md` - when to stop iterating and hand off to DevOps

---

## Core Constraints

### Workflow Progression
- ✅ **Always test locally first** with `mw experimental deploy`
- ✅ **Only automate when stable** - don't set up GitHub Actions until CLI works
- ❌ **Never mix** CLI and GitHub Actions in the same project phase

### Dockerfile Handling
- ❌ **Never let AI generate Dockerfiles** for this workflow
- ✅ **Delete existing Dockerfiles** if deployment fails (Railpack is bypassed when Dockerfile exists)
- ✅ **Let Railpack infer the build** - it's smarter than most AI-generated Dockerfiles

### Escalation Limits
- ⚠️ **After 2-3 deployment attempts fail**, escalate to DevOps
- ❌ **Don't deep-dive into container internals** without Docker expertise
- ✅ **Document errors and hand off** rather than iterate endlessly

---

## Key Facts

### Deployment Mechanics
- `mw experimental deploy` auto-detects Dockerfile **OR** uses Railpack
- `mittwald/zerodeploy-action` wraps the CLI for GitHub Actions (same behavior)
- Ingress is **automatically configured** with default `webapp` prefix (customize via `--uri-prefix`)
- Environment variables: `--env KEY=VALUE` or `--env-file path/to/.env`
- Wait for completion: `--wait` flag (default 600s timeout)

### Railpack Behavior
- Auto-detects: Node.js, Python, PHP, Ruby, Go, static sites, and more
- Requires: Buildpacks, build tools (npm, pip, composer, etc.)
- Failure modes: Exotic dependencies, complex monorepos, custom build chains
- Documentation: https://railpack.com/getting-started

### mStudio Integration
- **Troubleshooting happens in mStudio web UI**, not via CLI
- Logs, port inspection, container status are all GUI-based
- Port reconfiguration is done post-deployment in ingress settings
- Environment variables can be edited after deployment in mStudio

---

## Information Sources

### Official Documentation
- **GitHub Actions Guide**: https://developer.mittwald.de/docs/v2/guides/deployment/container-actions/
- **CLI Reference**: https://developer.mittwald.de/docs/v2/cli/reference/experimental/
- **Railpack Getting Started**: https://railpack.com/getting-started

### Skill Components
- **Playbooks**: Step-by-step execution guides for each phase
- **References**: Background knowledge, gotchas, and escalation criteria
