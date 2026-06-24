# Playbook: CLI Deploy (Local)

**Goal**: Deploy the application from the user's local machine using `mw experimental deploy` to validate the build before setting up automation.

---

## Pre-flight Checks

### 1. Verify working directory
Ensure the user is in the project root directory (where the main application code is):
```bash
pwd
ls -la
```

Look for indicators of a web project:
- `package.json` (Node.js)
- `requirements.txt` or `pyproject.toml` (Python)
- `composer.json` (PHP)
- `go.mod` (Go)
- Source code files

### 2. Check for existing Dockerfile

**CRITICAL**: Check if a Dockerfile exists:
```bash
ls -la Dockerfile docker-compose.yml
```

**If a Dockerfile exists**:
- ⚠️ This bypasses Railpack and may cause issues (especially if AI-generated)
- If deployment fails, **delete the Dockerfile and retry**
- See `references/pitfalls.md` for details

---

## Basic Deployment (No Environment Variables)

### Minimal command:
```bash
mw experimental deploy
```

**Flags explained**:
- If project ID not set as default: add `--project-id p-xxxxxx`

### Expected output:

```
  ✅ Pushing docker image .... done
  💡 Pushed image registry.p-kpbj8e.project.space/app-image:latest to registry
  ✅ Deploying .... done
  💡 Service app-541e474d-d656-4e69-a9d8-722f1bcae344 is now running
Reusing existing domain for hostname "webapp.p-kpbj8e.project.space"
  ✅ Setting up domain .... done

  ┌──────────────────────────────────────────────────────────────────────────────┐
  │  SUCCESS                                                                     │
  │  Container 313b5da8-2899-41f4-bac9-02881969a59c was successfully deployed    │
  └──────────────────────────────────────────────────────────────────────────────┘

```

**Do NOT parse the output, all information shown here is already known**

---

## Deployment with Environment Variables

### Option A: Pass via command line

For a few variables:
```bash
mw experimental deploy --wait \
  --env APP_ENV=production \
  --env API_KEY=sk-xxxxxx \
  --project-id p-xxxxxx
```

### Option B: Use an environment file

For many variables, create a `.env` file (do NOT commit to git):

**.env**:
```
APP_ENV=production
DATABASE_URL=mysql://user:pass@host/db
API_KEY=sk-xxxxxx
APP_SECRET=secret-value
```

Then deploy:
```bash
mw experimental deploy --wait \
  --env-file .env \
  --project-id p-xxxxxx
```

**Security reminder**: Add `.env` to `.gitignore`! See `references/secrets-management.md`.

---

## Custom Domain Prefix

The default URL prefix is `webapp`. To customize:
```bash
mw experimental deploy --wait \
  --uri-prefix myapp \
  --project-id p-xxxxxx
```

This creates: `https://myapp.p-xxxxxx.project.space`

---

## Monitoring Deployment

### While deployment runs:
- **Build logs** appear in the terminal
- Watch for:
  - Detected framework/language
  - Build steps executed
  - Image pushed successfully
  - Container created

### Common progress indicators:
```
✅ Checking dev tools ....
✅ Checking repository ....
✅ Building Docker image ....
✅ Setting up domain ....
```

---

## Parsing Output

### Success indicators:
- Exit code: `0`
- Message: "Container XYZ was successfully deployed" or similar
- URL provided: `https://...`
- Container ID provided ( example UUID ): `12345678-1234-abcd-efgh-123456789999`

### Failure indicators:
- Exit code: non-zero
- Error messages in output
- Build failed / Push failed / Deployment failed

---

## Common Deployment Errors

### "Build failed: missing dependencies"
- Application requires system packages not in base image
- Python: missing `gcc`, `python-dev`
- Node: missing `build-essential` for native modules
- Try once more, but if persistent → escalate

### "Dockerfile exists but build failed"
- Faulty Dockerfile (often AI-generated)
- **Solution**: Delete the Dockerfile and retry to use Railpack
- See `references/pitfalls.md` for details

### "Port configuration missing"
- Application doesn't expose a port or uses non-standard port
- Deploy anyway, then reconfigure in mStudio UI
- See `references/port-configuration.md`

---

## Next Steps

### If deployment succeeds:
1. **Note the deployment URL and container ID**
2. **Proceed to** `05-verify.md` to test the deployment
3. After verification, proceed to `03-setup-github-action.md` for automation

### If deployment fails:
1. **Check error message** in terminal output
2. **Load** `04-troubleshoot-deployment.md` for guidance
3. **Check** `references/pitfalls.md` for the 3 critical gotchas
4. If stuck after 2-3 attempts, load `references/when-to-escalate.md`
