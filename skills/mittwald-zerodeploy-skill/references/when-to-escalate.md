# When to Escalate

Knowing when to stop troubleshooting and hand off to an expert is a critical skill. This guide helps you recognize escalation triggers and document issues for effective handoff.

---

## Core Principle

**After 2-3 failed deployment attempts with different approaches, it's time to escalate.**

**Why?**
- ⏱️ **Time vs. value**: Endless troubleshooting wastes more time than consulting an expert
- 🎯 **Skill mismatch**: Complex container setups require specialized DevOps knowledge
- ⚠️ **Risk of making it worse**: Incorrect fixes can create deeper problems
- 💡 **Better alternatives exist**: Some projects need different deployment approaches

---

## Clear Escalation Triggers

### Escalate Immediately

**1. Railpack can't detect project type**
```
Error: Could not detect project type
Error: No buildpack found
Error: Build plan generation failed
```

**Why**: The project structure is too exotic for auto-detection. Requires custom Docker configuration.

**2. Multiple services in one repository**
- Monorepo with frontend + backend + worker
- Multiple language runtimes needed (Node + Python, etc.)
- Requires orchestration (Docker Compose, Kubernetes)

**Why**: Zerodeploy is designed for single-service deployments. Multi-service architectures need `deploy-container-action` or orchestration tools.

**3. Custom system dependencies required**
```
Error: Required package 'libvips-dev' not found
Error: Missing system library: librdkafka
```

**Why**: Railpack buildpacks have fixed base images. Custom dependencies require custom Dockerfiles.

**4. Database or infrastructure provisioning needed**
- App requires PostgreSQL, MySQL, Redis, etc.
- Needs persistent volumes for data storage
- Requires VPN or private networking

**Why**: Zerodeploy handles app deployment only. Infrastructure provisioning is a separate concern.

---

### Escalate After 2-3 Attempts

**1. Build succeeds but container crashes immediately**
- Container status: "Crashed" in mStudio
- Logs show startup errors or segmentation faults
- Rapid restart loops (restart count > 5)

**If after 2-3 attempts** (checking env vars, port config, logs), the issue persists → escalate.

**2. Build fails with cryptic errors**
```
Error: Segmentation fault (core dumped)
Error: Illegal instruction
Error: Build process killed
```

**Why**: These are low-level errors outside the scope of basic troubleshooting.

**3. Dependencies install but compilation fails**
```
npm ERR! Failed to compile native addon
ERROR: Failed building wheel for cryptography
```

**Try once or twice** with updated dependencies or different versions. If still failing → escalate.

**4. App works locally but fails in deployment**
- Local: `npm start` works fine
- Deployed: Container crashes or app doesn't respond

**After checking**:
- ✅ Environment variables are set correctly
- ✅ Port configuration is correct
- ✅ Logs don't show obvious errors

→ Escalate if still failing.

---

### Not Escalation Scenarios (Solve Yourself)

These are common issues with known solutions:

**1. Faulty Dockerfile present**
→ Delete Dockerfile, use Railpack (see `pitfalls.md`)

**2. Port mismatch (502 Bad Gateway)**
→ Reconfigure ingress in mStudio UI (see `port-configuration.md`)

**3. Missing environment variables**
→ Pass via `--env-file` or configure in GitHub Secrets (see `secrets-management.md`)

**4. Authentication failed**
→ Regenerate API token, update context or secrets

**5. Build fails due to missing `build` script in package.json**
→ Add build script or use `start` only for runtime-only apps

---

## What NOT to Do

### ❌ Don't try these without expertise:

**1. Writing custom Dockerfiles from scratch**
- Without Docker knowledge, you'll create more problems
- AI-generated Dockerfiles are often faulty (see `pitfalls.md`)

**2. Deep-diving into buildpack internals**
- Buildpacks are complex systems
- Debugging them requires specialized knowledge

**3. Iterating endlessly with minor config tweaks**
- "Maybe if I change this flag..."
- "Let me try this environment variable..."
- **After 2-3 attempts, stop and escalate**

**4. Modifying system packages or base images**
- "Let me add this apt-get command..."
- This requires custom Dockerfiles and expertise

**5. Debugging container networking or volumes**
- Requires understanding of Docker networking, overlay networks, etc.
- Not a beginner topic

---

## How to Escalate Effectively

### Step 1: Document the problem

**Gather information**:
- ✅ Exact error messages (copy from terminal or workflow logs)
- ✅ Full CLI command or GitHub Actions workflow used
- ✅ Project structure overview (language, framework, key files)
- ✅ What troubleshooting steps were already tried
- ✅ Environment: CLI or GitHub Actions? Project ID?

**Example documentation**:
```markdown
## Issue Summary
Deployment fails during build phase with "buildpack not found" error.

## Error Message

```
Error: Could not detect project type
No buildpack found for this project
```

## Project Structure
- Language: Python 3.11
- Framework: Custom ASGI app (not Flask/Django)
- Key files:
  - app.py (main entry point)
  - requirements.txt (dependencies)
  - custom_framework.py (custom web framework)

## Troubleshooting Attempted
1. Verified requirements.txt is at project root
2. Tried deleting Dockerfile (none existed)
3. Attempted deployment 3 times with same error

## Deployment Command
```bash
mw experimental deploy --wait --env-file .env --project-id p-abc123
```

## Request
Need guidance on whether this custom framework can work with Railpack or if custom Dockerfile is needed.
```

### Step 2: Provide access (if needed)

**For internal teams**:
- Share repository access
- Share project ID
- Share mStudio project access (if applicable)

**For external support**:
- Create a minimal reproducible example if possible
- Share relevant code snippets (not entire codebase)
- Provide logs and error messages

### Step 3: Suggest next steps (if you know them)

**Examples**:
- "I think this needs a custom Dockerfile - can you review?"
- "Is this project too complex for Railpack? Should we use deploy-container-action instead?"
- "Should I contact mittwald support for this platform-specific issue?"

### Step 4: Be available for follow-up

**The expert may need**:
- Additional information
- Access to test locally
- Clarification on project requirements

---

## Who to Escalate To

### Internal team escalation:
- **DevOps engineer**: For container, Docker, and infrastructure issues
- **Senior developer**: For framework-specific or architecture issues
- **Team lead**: For deciding whether to change deployment approach

### External escalation:
- **mittwald support**: For platform-specific issues or limitations
  - Use ticket system or support area at https://studio.mittwald.de (login to mStudio required)
  - Available for questions about platform capabilities, resource limits, or service issues
- **Railpack/Buildpack community**: For buildpack-specific issues
  - Railpack docs: https://railpack.com/getting-started

---

## Alternative Deployment Approaches

If zerodeploy isn't working, consider:

### Option 1: deploy-container-action (Explicit Docker)
**Use when**:
- ✅ Project requires custom system dependencies
- ✅ Multi-stage builds needed
- ✅ Full control over container environment required

**Trade-off**: Requires Docker expertise, more maintenance.

**Docs**: https://developer.mittwald.de/docs/v2/guides/deployment/container-actions/

### Option 2: Traditional hosting (Non-containerized)
**Use when**:
- ✅ Project doesn't fit container model (exotic architecture)
- ✅ Legacy app with unusual requirements
- ✅ Simpler hosting model preferred

**Trade-off**: Less scalable, more manual setup.

---

## Recognizing Project Complexity Early

**Before starting deployment**, assess complexity:

### Good fit for zerodeploy:
- ✅ Single web application
- ✅ Standard framework (Express, Flask, Laravel, Rails, Next.js)
- ✅ Standard dependencies (npm, pip, composer packages)
- ✅ Conventional project structure

### Possible fit (proceed cautiously):
- ⚠️ Less common framework (but still uses npm/pip/composer)
- ⚠️ Some native dependencies (might work, might not)
- ⚠️ Custom build scripts (if they follow conventions)

### Poor fit (consider alternatives):
- ❌ Monorepo with multiple services
- ❌ Multi-language runtime (Node + Python + Go, etc.)
- ❌ Custom build toolchains (Bazel, Buck, custom scripts)
- ❌ Requires specific system libraries or kernel modules
- ❌ Needs database, cache, queue services provisioned

**If project is in the "poor fit" category**, escalate before attempting deployment.

---

## Success Metrics for Escalation

**Escalation is successful when**:
- ✅ Issue is resolved by expert in < 1 hour (vs. many hours of your time)
- ✅ You learn something new for next time
- ✅ Project is deployed successfully or alternative approach is identified
- ✅ Team has documentation for handling similar cases

---

## Related References

- `pitfalls.md` - The 3 critical gotchas (check these first before escalating)
- `railpack-overview.md` - Understanding Railpack limits
- Playbook `04-troubleshoot-deployment.md` - Systematic debugging before escalation
