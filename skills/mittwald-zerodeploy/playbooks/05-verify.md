# Playbook: Verify Deployment

**Goal**: Confirm the deployed application is working correctly and accessible to users.

---

## Verification Checklist

### ✅ Container Status

### ✅ HTTP Accessibility

### ✅ Application Functionality

### ✅ Environment Variables

### ✅ Logs Show Healthy Startup

---

## Step 1: Check Container Status in mStudio

### Navigate to container

1. **Go to**: mStudio → Projects → [Your Project] → Containers
2. **Find your container**: Look for deployment URL prefix or container ID
3. **Check status indicator**:
   - **Running**: Good! Proceed to next checks
   - **Starting**: Wait 30-60 seconds, then refresh
   - **Crashed**: Container failed to start → load `04-troubleshoot-deployment.md`
   - **Stopped**: Container was manually stopped → restart it

### Verify basic info

- **Image**: Should show recent timestamp
- **Created**: Should match deployment time
- **Restarts**: Should be 0 (or low number if recently fixed issues)
- **High restart count** (10+): App is crash-looping → check logs!

---

## Step 2: Test HTTP Accessibility

### Get the deployment URL

**From CLI output**:

```
Deployment successful!
URL: https://webapp.p-xxxxxx.project.space
```

**From mStudio UI**:

- Container details page → Ingress tab
- Look for "Public URLs" section

### Test the URL

**Method 1: Browser**

1. Open deployment URL in browser
2. Should load without errors
3. Check if content renders correctly

**Method 2: curl (terminal)**

```bash
curl -I https://webapp.p-xxxxxx.project.space
```

**Expected response**:

```
HTTP/2 200 OK
content-type: text/html
...
```

### Common HTTP errors

**502 Bad Gateway**:

- Container is running but app isn't listening on expected port
- Load `references/port-configuration.md`
- Reconfigure ports in mStudio ingress settings

**504 Gateway Timeout**:

- App is taking too long to respond
- Check logs for startup errors or slow initialization

**404 Not Found**:

- App is running but path is incorrect
- Try base path: `/` or `/index.html`
- Check app's routing configuration

**Connection refused / Can't connect**:

- Container not running or ingress not configured
- Check container status in mStudio
- Verify ingress rules are set

---

## Step 3: Verify Application Functionality

### Basic functionality tests

**Static site or Single Page App**:

- ✅ Page loads completely
- ✅ Stylesheets applied (not raw HTML)
- ✅ JavaScript executes (check console for errors)
- ✅ Images and assets load correctly

**API or Backend Service**:

- ✅ Health check endpoint responds (e.g., `/health`, `/api/status`)
- ✅ API returns expected data format (JSON, XML, etc.)
- ✅ Authentication works if applicable
- ✅ Database connections succeed (if app uses DB)

**Full-stack Application**:

- ✅ Homepage renders correctly
- ✅ User interactions work (buttons, forms, navigation)
- ✅ API calls succeed (check browser network tab)
- ✅ No console errors in browser dev tools

### Framework-specific checks

**Node.js/Express**:

```bash
curl https://webapp.p-xxxxxx.project.space
# Should return HTML or JSON depending on app
```

**Python/Flask or Django**:

```bash
curl https://webapp.p-xxxxxx.project.space
# Check for framework-specific output
```

**PHP/Laravel**:

```bash
curl https://webapp.p-xxxxxx.project.space
# Should show Laravel welcome page or app homepage
```

**React/Vue/Angular SPA**:

- Open in browser, check if app loads
- Open browser console (F12) → check for JavaScript errors
- Verify assets load from correct paths

---

## Step 4: Validate Environment Variables

### Check if secrets are applied

**Method 1: Test feature that uses env var**

- If app uses `DATABASE_URL` → test database query
- If app uses `API_KEY` → test API call
- If app uses `APP_SECRET` → test authentication

**Method 2: Check app logs for env var issues**

- Navigate to: mStudio → Container → Logs
- Look for errors like:
  - `DATABASE_URL is not defined`
  - `Missing required environment variable`
  - `Connection string not found`

**Method 3: Debug endpoint (if available)**

- Some apps have `/debug` or `/config` endpoints
- **CAUTION**: Only use in development/testing
- Never expose sensitive env vars in production endpoints!

### If env vars are missing or incorrect

**For CLI deployments**:

- Verify `--env` or `--env-file` flags were used
- Check `.env` file syntax (KEY=VALUE, no spaces around `=`)
- Redeploy with correct environment variables

**For GitHub Actions**:

- Check GitHub Secrets are configured correctly
- Verify workflow creates `.env` file properly
- Check workflow logs for env var creation step

**Update in mStudio UI** (post-deployment):

1. Go to: Container → Environment variables tab
2. Add or edit variables directly
3. Save → Container restarts automatically
4. Verify in logs that new values are applied

---

## Step 5: Review Container Logs

### Access logs

1. **Navigate to**: mStudio → Container → Logs tab
2. **View recent logs** (last 100-500 lines)
3. **Look for**:
   - Successful startup messages
   - Port binding confirmation
   - No uncaught exceptions
   - No repeated errors

### Healthy startup patterns

**Node.js/Express**:

```
Server listening on port 3000
Connected to database
Environment: production
Ready to accept connections
```

**Python/Flask**:

```
* Running on http://0.0.0.0:5000
* Debug mode: off
```

**Python/Django**:

```
Starting development server at http://0.0.0.0:8000/
Quit the server with CONTROL-C.
```

**PHP/Laravel**:

```
INFO  Server running on [http://0.0.0.0:8000]
```

**Ruby/Rails**:

```
=> Booting Puma
=> Rails 7.0.0 application starting in production
=> Run `bin/rails server --help` for more startup options
Puma starting in single mode...
* Listening on http://0.0.0.0:3000
```

### Warning signs in logs

**Repeated restarts**:

```
Starting application...
Error: Cannot connect to database
Starting application...
Error: Cannot connect to database
```

→ App is crash-looping, check environment variables

**Port binding errors**:

```
Error: listen EADDRINUSE: address already in use :::8080
```

→ Rare in containerized environment, may indicate config issue

**Missing dependencies**:

```
ModuleNotFoundError: No module named 'flask'
Cannot find module 'express'
```

→ Build process didn't install dependencies correctly → escalate

---

## Final Verification

### Deployment is successful if

- ✅ Container status is "Running" in mStudio
- ✅ Deployment URL is accessible via browser or curl
- ✅ Application renders or responds correctly
- ✅ Environment variables are applied (if needed)
- ✅ Logs show healthy startup without errors
- ✅ No crash-loops or repeated restarts

---

## Post-Verification Actions

### If verification passes

**For CLI deployments**:

- ✅ Deployment workflow is complete
- ✅ Consider transitioning to GitHub Actions (load `03-setup-github-action.md`)
- ✅ Document any environment variables needed
- ✅ Share deployment URL with stakeholders

**For GitHub Actions deployments**:

- ✅ Automation is working correctly
- ✅ Monitor subsequent deployments for consistency
- ✅ Set up deployment notifications if desired
- ✅ Document workflow for team members

### If verification fails

**Load** `04-troubleshoot-deployment.md` and systematically debug:

1. Identify failure stage (container, HTTP, app functionality)
2. Check the 3 critical gotchas
3. Review logs in mStudio
4. Fix and redeploy
5. Verify again

### Edge cases to monitor

**First request is slow (cold start)**:

- Container may take 5-10 seconds to warm up
- Normal for first request after deployment
- Subsequent requests should be fast

**Intermittent errors**:

- May indicate resource constraints or configuration issues
- Check CPU/memory usage in mStudio
- Review logs for patterns

**Different behavior than local**:

- Environment differences (NODE_ENV, paths, etc.)
- Check environment variables are set correctly
- Verify build artifacts are included in deployment

---

## Next Steps

### Success path

- ✅ Deployment verified and working
- ✅ Share URL with users or team
- ✅ Monitor logs for any issues
- ✅ Set up automated deployments (if not already done)

### Troubleshooting path

- 🔧 Issues found during verification
- 🔍 Load `04-troubleshoot-deployment.md`
- 📖 Check `references/pitfalls.md` for common gotchas
- 🚨 Escalate if needed (load `references/when-to-escalate.md`)
