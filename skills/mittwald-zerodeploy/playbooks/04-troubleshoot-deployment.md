# Playbook: Troubleshoot Deployment

**Goal**: Diagnose and fix common deployment failures using mStudio UI and systematic debugging.

---

## Troubleshooting Strategy

### 1. Identify the failure stage

- **Build failure**: Error during image build (dependencies, compilation)
- **Push failure**: Error uploading image to registry
- **Deployment failure**: Container created but won't start
- **Runtime failure**: Container starts but app doesn't work

### 2. Gather information

- CLI/workflow error output
- mStudio container logs
- Container status in mStudio UI

### 3. Apply known fixes

- Check the 3 critical gotchas (see below)
- Review common error patterns
- Attempt one fix at a time

### 4. Know when to escalate

- After 2-3 failed attempts
- Load `references/when-to-escalate.md`

---

## Critical Gotcha #1: Faulty Dockerfile

### Symptom

- Build fails with Docker-related errors
- Error messages mention Dockerfile syntax or invalid instructions
- Build works on one machine but not another

### Root cause

- AI-generated Dockerfiles are often broken or use wrong base images
- When a Dockerfile exists, Railpack is bypassed completely
- User may not even realize there's a Dockerfile

### Detection

```bash
ls -la Dockerfile docker-compose.yml .dockerignore
```

### Solution

**Delete the Dockerfile and let Railpack handle the build:**

```bash
rm Dockerfile
rm docker-compose.yml  # If exists
```

Then retry deployment:

```bash
mw experimental deploy --wait --project-id p-xxxxxx
```

### Why this works

- Railpack is usually smarter than AI-generated Dockerfiles
- Railpack uses tested buildpacks for each language/framework
- Removes human error from the container build process

---

## Critical Gotcha #2: Hidden Port Configuration

### Symptom

- Container starts successfully
- Deployment completes without errors
- App is not accessible at deployment URL (502 Bad Gateway, timeout)

### Root cause

- App listens on unexpected port (not 8080, 3000, 5000, etc.)
- Port is hardcoded in obscure config file or even source code
- Framework uses non-standard default port

### Detection

Ask user to check logs in mStudio:

1. Navigate to: `mStudio → Project → Containers`
2. Find the container (search by deployment URL prefix)
3. Click on container → View logs
4. Look for lines like:
   - `Listening on port 4200`
   - `Server running at http://0.0.0.0:9000`
   - `Started on :8081`

### Solution

**Deploy first, reconfigure ports afterward:**

1. **Let deployment complete** (even if app isn't accessible)
2. **Find the actual port** from container logs
3. **Reconfigure in mStudio UI**:
   - Go to: Container → Ingress settings
   - Update port mapping (e.g., HTTP → 8081)
   - Save and wait for container restart

### Framework-specific ports

- **Angular dev server**: 4200
- **Vue/Vite**: 5173
- **Create React App**: 3000
- **Flask**: 5000
- **Django**: 8000
- **Laravel**: 8000
- **Rails**: 3000
- **Express**: Usually 3000 or 8080

See `references/port-configuration.md` for more details.

---

## Critical Gotcha #3: Exotic Project (Can't Be Fixed)

### Symptom

- Railpack can't detect project type
- Build fails with cryptic errors about missing tools
- Multiple programming languages in one repo
- Custom build scripts that don't follow conventions

### Root cause

- Project is too complex for Railpack's auto-detection
- Unusual dependencies or build toolchains
- Monorepo with multiple services
- Non-standard project structure

### Detection signs

Close inspection of build logs needed. Look for errors
indicating that infered railpack build plan does not fit
the project.

### When to stop trying

- **After 2-3 failed deployment attempts**
- Build errors don't make sense or are too cryptic
- Project has custom Docker setup requirements
- Multiple services need to run together

### Solution

**Escalate to DevOps immediately:**

1. **Load** `references/when-to-escalate.md`
2. **Document the error messages** exactly
3. **Provide project structure** overview
4. **Hand off to DevOps engineer** or mittwald support (via ticket system or support area at https://studio.mittwald.de)

**What NOT to do:**

- ❌ Try to write a custom Dockerfile from scratch
- ❌ Attempt to debug Railpack internals
- ❌ Keep iterating with minor config changes
- ❌ Spend more than 1-2 hours troubleshooting

---

## Common Error Patterns

### "npm ERR! missing script: build"

**Cause**: Railpack expects `npm run build` but script doesn't exist in package.json

**Solutions**:

1. **Add build script** to package.json:

   ```json
   {
     "scripts": {
       "build": "echo 'No build needed'"
     }
   }
   ```

2. **Or specify start script only** (for runtime-only apps like Express servers)

---

### "pip: command not found" or "requirements.txt: not found"

**Cause**: Python project but Railpack can't find requirements file

**Solutions**:

1. **Ensure requirements.txt exists** at project root
2. **Or use pyproject.toml** (modern Python standard)
3. Verify file is committed to git

---

### "Composer dependencies require ext-*"

**Cause**: PHP project requires system extensions not in base image

**Solution**: This is an escalation case - custom Dockerfile needed with extensions

---

### "EACCES: permission denied"

**Cause**: Build process trying to write to protected directories

**Solution**:

- Usually a Dockerfile issue
- Delete Dockerfile and use Railpack
- If persists → escalate

---

### "Cannot connect to database"

**Cause**: Environment variable for database connection not set or incorrect

**Solutions**:

1. **Check `.env` file** contains `DATABASE_URL` or similar
2. **In GitHub Actions**: Verify secret is set and passed to workflow
3. **In mStudio**: Edit environment variables post-deployment

---

## Using mStudio for Debugging

### Access container logs

1. **Navigate to**: `mStudio → Projects → [Your Project] → Containers`
2. **Find your container**: Look for deployment URL prefix or container ID
3. **Click container name** → View logs
4. **Check recent logs** for:
   - Startup errors
   - Port binding messages
   - Uncaught exceptions
   - Configuration errors

### Check container status

**Status indicators**:

- **Running**: Container is healthy
- **Starting**: Container is initializing (wait a moment)
- **Crashed**: Container failed to start or died (check logs!)
- **Stopped**: Container was manually stopped

### Edit environment variables

1. **Container details page** → Environment variables tab
2. **Add/edit variables** directly in UI
3. **Save** → Container restarts automatically
4. **Check logs** to verify changes took effect

### Reconfigure ports and ingress

1. **Container details page** → ports tab
2. **View current port mappings**
3. **Edit mappings** if needed (e.g., HTTP → 8080)
4. **Update ingress rules** if app needs multiple ports
5. **Save** and test URL again

---

## Systematic Debugging Process

### Step 1: Check the 3 gotchas first

1. ✅ Dockerfile present? → Delete and retry
2. ✅ Port mismatch? → Check logs, reconfigure in UI
3. ✅ Exotic project? → Escalate if 2-3 attempts failed

### Step 2: Review error output

- Copy exact error message from CLI or GitHub Actions
- Look for patterns in common errors above
- Note which stage failed (build, push, deploy, runtime)

### Step 3: Check mStudio logs

- Navigate to container in mStudio UI
- Read the most recent logs
- Look for application-level errors

### Step 4: Verify environment variables

- Are all required secrets configured?
- In CLI: Was `--env-file` used correctly?
- In GitHub Actions: Are secrets passed to workflow?
- In mStudio: Are variables set correctly in UI?

### Step 5: Test in isolation

- Can the app start locally? (`npm start`, `python app.py`, etc.)
- Are dependencies installed correctly locally?
- Does the app work with the same environment variables?

### Step 6: Decide to continue or escalate

- **If progress is made**: Try once more with new fix
- **If no progress after 2-3 attempts**: Load `references/when-to-escalate.md`

---

## Next Steps

### If issue is resolved

- **Load** `05-verify.md` to confirm deployment works
- **Document the fix** for future reference
- **Update environment or workflow** if config changed

### If stuck

- **Load** `references/when-to-escalate.md` to determine if escalation is appropriate
- **Document all troubleshooting steps taken** for handoff
- **Provide error logs** to DevOps or support
