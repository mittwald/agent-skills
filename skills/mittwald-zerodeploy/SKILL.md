---
name: mittwald-zerodeploy
description: Deploy an arbitrary application from your local machine or a Git repository to mittwald mStudio. Use when the user mentions "deploy to Mittwald", "move to mStudio", "Container Hosting auf Mittwald", "stack_deploy", or asks for help deploying a workload (K8s, Docker Compose, VPS, another hoster, another mStudio project) onto Mittwald. Source is open, target is always mStudio.
---

# mittwald-zerodeploy

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
   - Check CLI, Docker and Railpack are installed and authenticated
   - **Have the user confirm the target project** (use context project / pick another / create new)
   - Check an existing project for colliding services and hostnames

2. **Load** `playbooks/02-cli-deploy-local.md`
   - Derive `--uri-prefix`, `--service-name`, `--image-name` from the app name
   - Run `mw experimental deploy` from project root (no `--wait`, no output piping)
   - Pass `--env PORT=<port>` when a Dockerfile exposes a port other than 80
   - Poll the URL with `curl` until the app answers

3. **Load** `playbooks/05-verify.md`
   - Check container status (MCP tools first, web UI as fallback)
   - Test HTTP endpoints and validate responses
   - Confirm environment variables are applied correctly

### Phase 2: Automation (GitHub Actions)

**Goal**: Set up continuous deployment after local testing succeeds.

1. **Load** `playbooks/03-setup-github-action.md`
   - Create `.github/workflows/zerodeploy.yml`
   - Configure GitHub secrets (`MITTWALD_API_TOKEN`, `MITTWALD_PROJECT_ID`)
   - Handle runtime secrets via workflow `.env` generation
   - Test with manual workflow dispatch

2. **Test automated deployment**
   - Trigger workflow manually
   - Monitor workflow logs for errors

3. **Load** `playbooks/05-verify.md` again
   - Confirm automated deployment produces same result as CLI

### Troubleshooting (As Needed)

**When deployment fails or behaves unexpectedly:**

- **Load** `playbooks/04-troubleshoot-deployment.md`
  - Inspect via `mittwald_container_list`, `mittwald_container_logs`, `mittwald_domain_virtualhost_list`
  - Compare log port with virtualhost port before touching any Dockerfile
  - Identify common error patterns
  - Delete a faulty Dockerfile only if the build fails

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

- ✅ **Always confirm the target project** with the user (name + short ID), even on "just do it": the context project may be stale or shared
- ✅ **Always test locally first** with `mw experimental deploy`
- ❌ **Never rely on default names** (`webapp`, `app-<project-id>`, `app-image`): they collide with and take over existing services and hostnames
- ✅ **Only automate when stable** - don't set up GitHub Actions until CLI works
- ❌ **Never mix** CLI and GitHub Actions in the same project phase

### Dockerfile Handling

- ❌ **Never let AI generate Dockerfiles** for this workflow
- ✅ **Delete existing Dockerfiles** only if the **build** fails (Railpack is bypassed when Dockerfile exists); a 502 after a successful deploy is a port issue
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
- Ingress is **automatically configured**; an existing hostname with the same `--uri-prefix` is reused and retargeted
- Environment variables: `--env KEY=VALUE` or `--env-file path/to/.env`
- The CLI sets `PORT=80` in the container unless `--env PORT=...` is passed; the ingress targets the first `EXPOSE` port
- The command always waits for the service and TLS (`--wait` is ignored; `--wait-timeout` defaults to 600s)

### Railpack Behavior

- Auto-detects: Node.js, Python, PHP, Ruby, Go, static sites, and more
- Requires: Buildpacks, build tools (npm, pip, composer, etc.)
- Failure modes: Exotic dependencies, complex monorepos, custom build chains
- Documentation: https://railpack.com/getting-started

### mStudio Integration

- **Troubleshoot with the mittwald MCP tools first** (`mittwald_container_list`, `mittwald_container_logs`, `mittwald_domain_virtualhost_list`), then `mw container …` / `mw domain virtualhost …`
- Send the user to the mStudio web UI only as a fallback
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
