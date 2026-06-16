# Critical Pitfalls in Zerodeploy Workflows

This document expands on the **3 most common gotchas** that cause deployment failures. Understanding these early saves hours of debugging.

---

## Pitfall #1: Faulty Pre-existing Dockerfiles

### The Problem

**When a Dockerfile exists in the project root, Railpack is completely bypassed.** The CLI and GitHub Action will use the Dockerfile directly, and if it's broken, the deployment will fail.

**Why is this a problem?**
- AI coding agents often generate Dockerfiles that look plausible but contain subtle errors
- Copy-pasted Dockerfiles may use wrong base images or incompatible commands
- Dockerfile may be outdated or incompatible with current codebase
- Multi-stage builds can be complex and error-prone

### Detection

Check for Dockerfile presence:
```bash
ls -la Dockerfile docker-compose.yml .dockerignore
```

**Warning signs**:
- Build fails with Docker-specific errors
- Error messages reference Dockerfile lines
- Build works on some machines but not others
- "COPY failed" or "RUN command failed" in logs

### Why This Happens

Developers (or AI assistants) create a Dockerfile thinking it will help, but:
- They don't fully understand Docker internals
- Base image choice is wrong for the framework
- Build commands don't match project structure
- File paths in COPY commands are incorrect
- Missing dependencies in the image

### The Solution

**Delete the Dockerfile and let Railpack handle the build:**

```bash
rm Dockerfile
rm docker-compose.yml  # If exists
rm .dockerignore       # If exists
git add -A
git commit -m "Remove faulty Dockerfile, use Railpack auto-detection"
git push
```

Then retry deployment:
```bash
mw experimental deploy --wait --project-id p-xxxxxx
```

### Why This Works

- **Railpack uses battle-tested buildpacks** maintained by experts
- **Buildpacks are framework-specific** and updated regularly
- **Auto-detection is smarter than guessing** what the app needs
- **Less human error** in the build process
- **Consistent builds** across different environments

### When NOT to Delete the Dockerfile

Keep the Dockerfile if:
- ✅ It's maintained by a DevOps team and tested
- ✅ It's part of a production-grade setup
- ✅ The project requires system dependencies not available in buildpacks
- ✅ Multiple services need custom orchestration

In these cases, you're outside the "zerodeploy" use case and should use `deploy-container-action` instead.

### Prevention

**Best practice**: Don't let AI assistants create Dockerfiles for projects intended for zerodeploy workflows. If a Dockerfile is needed, involve a DevOps engineer.

---

## Pitfall #2: Hidden Port Configurations

### The Problem

**Apps may listen on ports that don't match the default expectations**, and the port might be hardcoded in obscure places:
- Config files deep in the project
- Environment variables not documented
- Framework defaults that differ from convention
- Vibe-coded apps with random port choices

**The result**: Deployment succeeds, container runs, but the app is not accessible (502 Bad Gateway).

### Detection

**Symptom checklist**:
- ✅ Deployment completed successfully
- ✅ Container status is "Running" in mStudio
- ❌ Deployment URL returns 502 Bad Gateway or timeout
- ❌ App not responding on expected URL

**Check the logs** in mStudio:
1. Navigate to: Container → Logs
2. Look for startup messages like:
   - `Listening on port 4200`
   - `Server running at http://0.0.0.0:9000`
   - `Started on :8081`

### Common Port Patterns

| Framework/Tool | Default Port | Notes |
|---|---|---|
| Express (Node.js) | 3000 or 8080 | Often configurable via `PORT` env var |
| Create React App (dev) | 3000 | Production builds are static files |
| Angular CLI (dev) | 4200 | Not used in production |
| Vue/Vite (dev) | 5173 | Not used in production |
| Next.js | 3000 | Configurable via `-p` flag |
| Flask (Python) | 5000 | Often configurable via env var |
| Django (Python) | 8000 | Configurable in settings |
| Laravel (PHP) | 8000 | `php artisan serve` default |
| Rails (Ruby) | 3000 | Puma default |
| Go (standard HTTP) | 8080 | Varies by implementation |

### The Solution

**Deploy first, reconfigure afterward:**

1. **Let the deployment complete** even if the app isn't accessible yet
2. **Find the actual port** from container logs in mStudio
3. **Reconfigure ingress in mStudio UI**:
   - Navigate to: Container → Ingress tab
   - Update port mapping (e.g., HTTP → 8081 instead of HTTP → 8080)
   - Save changes
   - Container may restart automatically

4. **Test the URL again** after reconfiguration

### Why This Works

- **mStudio ingress is flexible** - you can change port mappings after deployment
- **No need to rebuild** the entire image
- **Faster than debugging** why the app chose a specific port
- **Works even when port is hardcoded** in the application

### Prevention (for new projects)

**Configure port via environment variable**:

Most frameworks support `PORT` env var:

**Node.js/Express**:
```javascript
const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Server on port ${port}`));
```

**Python/Flask**:
```python
import os
port = int(os.environ.get('PORT', 5000))
app.run(host='0.0.0.0', port=port)
```

**Python/Django** (in settings.py):
```python
# Use PORT env var if available
import os
PORT = int(os.environ.get('PORT', 8000))
```

Then pass `--env PORT=8080` during deployment to standardize.

### When to Escalate

If the app uses **multiple ports** (e.g., HTTP + WebSocket + gRPC), this is beyond zerodeploy scope. The project needs custom ingress configuration → escalate to DevOps.

---

## Pitfall #3: Exotic Projects Won't Always Work

### The Problem

**Railpack has limits.** It's designed for standard web applications with conventional structures. Complex or unusual projects may not work with auto-detection.

**What qualifies as "exotic"?**
- ✅ Monorepos with multiple services
- ✅ Custom build toolchains (Bazel, Buck, etc.)
- ✅ Multi-language projects (e.g., Python backend + Node.js frontend in one repo)
- ✅ Unusual dependency management (custom package resolution)
- ✅ Legacy codebases with non-standard structures
- ✅ Projects requiring specific system libraries or kernel modules

### Detection

**Error patterns**:
```
Could not detect project type
No buildpack found for this project
Build plan generation failed
Unsupported dependency: <some exotic tool>
```

**Behavioral signs**:
- Railpack can't determine language/framework
- Build starts but fails on missing tools
- Dependencies install but compilation fails
- Multiple failed attempts with different approaches

### Why This Happens

Railpack relies on:
- **Conventional project structures** (e.g., `package.json` at root)
- **Standard build tools** (npm, pip, composer, etc.)
- **Well-known frameworks** (Express, Flask, Laravel, etc.)

When projects deviate from conventions, auto-detection breaks down.

### The Solution

**Recognize the limits early and escalate:**

**After 2-3 failed deployment attempts**, it's time to hand off to a DevOps engineer or mittwald support.

**What to do**:
1. ✅ Document the exact error messages
2. ✅ Provide an overview of the project structure
3. ✅ List any unusual dependencies or build requirements
4. ✅ Hand off to someone with Docker/container expertise
5. ✅ Contact mittwald support via ticket system or support area at https://studio.mittwald.de (login required)

**What NOT to do**:
- ❌ Attempt to write a custom Dockerfile from scratch (without Docker knowledge)
- ❌ Deep-dive into Railpack or buildpack internals
- ❌ Try 10 different variations of the same deployment
- ❌ Spend more than 2 hours troubleshooting

### Why Escalation is the Right Choice

- **Time vs. value**: Endless troubleshooting wastes more time than consulting an expert
- **Skill mismatch**: Complex container setups require specialized knowledge
- **Risk of making it worse**: Incorrect fixes can create deeper problems
- **Better alternatives exist**: For complex projects, `deploy-container-action` with explicit Dockerfiles may be the right tool

### Prevention

**Evaluate project complexity before starting**:

**Good candidates for zerodeploy**:
- ✅ Standard web apps (Node.js, Python, PHP, Ruby)
- ✅ Single service per repository
- ✅ Conventional project structure
- ✅ Standard dependency management

**Bad candidates for zerodeploy**:
- ❌ Monorepos with multiple services
- ❌ Custom build toolchains
- ❌ Multi-language projects
- ❌ Projects with exotic dependencies

For complex projects, start with the `deploy-container-action` approach (explicit Dockerfile + stack.yaml) instead of zerodeploy.

---

## Summary: The 3 Gotchas at a Glance

| Gotcha | Symptom | Quick Fix | Escalate If... |
|---|---|---|---|
| **Faulty Dockerfile** | Build fails with Docker errors | Delete Dockerfile, use Railpack | Dockerfile is required for custom dependencies |
| **Hidden Port** | Container runs, URL returns 502 | Check logs, reconfigure ingress in mStudio | App uses multiple ports or custom protocols |
| **Exotic Project** | Railpack can't detect or build fails | **Escalate immediately** | Always escalate after 2-3 failed attempts |

---

## Related References

- `when-to-escalate.md` - Detailed escalation criteria and handoff process
- `port-configuration.md` - Framework-specific port patterns and configuration
- `railpack-overview.md` - What Railpack can and cannot detect
