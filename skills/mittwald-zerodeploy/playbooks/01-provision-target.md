# Playbook: Provision Target

**Goal**: Verify the mittwald mStudio environment is ready for deployment.

---

## Prerequisites Check

Before deploying, confirm the user has:

- Active mittwald mStudio account
- At least one project in mStudio
- API token generated from mStudio
- mittwald CLI installed locally

---

## Step 1: Verify CLI Installation

Check if the mittwald CLI is installed:

```bash
mw --version
```

**Expected output**: Version string (e.g., `@mittwald/cli/1.25.0 darwin-arm64 node-v20.19.3`)

**If not installed**: Direct user to install via:

```bash
npm install -g @mittwald/cli
# or
brew install mittwald/cli/mw
```

`mw experimental deploy` also requires **Docker** and **Railpack** in the `PATH`, even when the project has its own Dockerfile. The first deploy step ("Checking dev tools") fails if either is missing:

```bash
docker --version
railpack --version
```

---

## Step 2: Check Authentication

Verify the user has an API token configured:

```bash
mw login status
```

**If no token is set**: Guide user to:

1. Log in to mStudio (https://studio.mittwald.de)
2. Navigate to **Profile** → **API Tokens**
3. Create a new token with **`api_write`** scope
4. Set the token via CLI (prompts for the token):

   ```bash
   mw login token
   ```

---

## Step 3: Choose and Confirm the Target Project (REQUIRED)

**Never deploy without an explicit confirmation of the target project.** This applies even when the user says "just do it" / "mach einfach". That instruction lets you skip other questions, but never this one.

**Why**: The project stored in the CLI context may be stale or shared with other workloads. A deploy there can overwrite an existing service (the default service name is `app-<project-id>`) or take over an existing hostname (the default `webapp.<short-id>.project.space` is reused if it exists).

### 3a. Show the current context project

```bash
mw context get
```

**Look for**: the project ID line. Then resolve it to a name and short ID:

```bash
mw project get <project-id>
```

With the mittwald MCP server, use `mittwald_project_get` (and `mittwald_project_list` for the alternatives).

### 3b. Ask the user

Present the context project by **name and short ID** (e.g. `"Container Test" (p-whvzpe)`) and offer exactly these options:

1. **Use this project**
2. **Pick another existing project** - list them with `mw project list` / `mittwald_project_list`
3. **Create a new project** - `mw project create --description "<app name>"` / `mittwald_project_create`

If no project is set in the context, skip straight to options 2 and 3.

### 3c. If the user picked an existing project: check for collisions

List what already runs there before deploying:

- `mittwald_container_list` / `mw container list --project-id <project-id>`: existing services and their names
- `mittwald_domain_virtualhost_list` / `mw domain virtualhost list --project-id <project-id>`: existing hostnames with their target container and port

Make sure the service name and hostname you plan to use in `02-cli-deploy-local.md` don't exist yet, unless the user explicitly wants to replace that service or hostname.

### 3d. Remember the project ID

Pass `--project-id <project-id>` explicitly on every deploy command. Don't rely on the CLI context; it is easy to change it from another shell and forget about it.

---

## Step 4: Verify Project Access

`mw project get <project-id>` from Step 3a already proves access.

**If access denied**: Token may lack permissions (needs `api_write`) or project ID is incorrect.

---

## Step 5: Confirm Working Directory

Make sure the user is in the root directory of the application they want to deploy:

```bash
pwd
ls -la
```

**Verify presence of**:

- Application source code
- Build configuration files (package.json, requirements.txt, composer.json, etc.)
- **NO faulty Dockerfile** (if present, flag for review in next playbook)

---

## Validation Checklist

Before proceeding to deployment, confirm:

- ✅ CLI installed and accessible
- ✅ Docker and Railpack installed
- ✅ API token configured and valid
- ✅ Target project **explicitly confirmed by the user** (name + short ID)
- ✅ No collision with existing services or hostnames in that project
- ✅ Project is accessible with current token
- ✅ User is in the correct application directory

---

## Common Issues

### Issue: "Authentication failed"

**Cause**: Token expired or invalid  
**Solution**: Generate a new API token in mStudio and run `mw login token --overwrite`

### Issue: "Project not found"

**Cause**: Wrong project ID or insufficient permissions  
**Solution**: Verify project ID with `mw project list` and check token permissions

### Issue: "CLI command not found"

**Cause**: CLI not in PATH or not installed  
**Solution**: Reinstall CLI or check PATH configuration

---

## Next Step

Once all checks pass, proceed to **02-cli-deploy-local.md** to test the deployment.
