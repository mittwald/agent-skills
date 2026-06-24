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

**Expected output**: Version number (e.g., `2.x.x`)

**If not installed**: Direct user to install via:

```bash
npm install -g @mittwald/cli
# or
brew install mittwald/cli/mw
```

---

## Step 2: Check Authentication

Verify the user has an API token configured:

```bash
mw context
```

**Expected output**: Should show configured API token (partially masked)

**If no token is set**: Guide user to:

1. Log in to mStudio (https://studio.mittwald.de)
2. Navigate to **Profile** → **API Tokens**
3. Create a new token with "Container Management" permissions
4. Set the token via CLI:

   ```bash
   mw context set --api-token YOUR_TOKEN_HERE
   ```

---

## Step 3: Identify Project ID

The user needs to know their target project ID. Check current context:

```bash
mw context
```

**Look for**: `projectId` field in the output

### If project ID is NOT set

List available projects:

```bash
mw project list
```

**Have the user choose** the target project from the list.

### Option A: Set project in context (persistent)

```bash
mw context set --project-id p-XXXXXX
```

### Option B: Pass project ID per deployment (explicit)

Store the project ID to use later with `--project-id` flag in deploy commands.

---

## Step 4: Verify Project Access

Test that the project is accessible and the token has proper permissions:

```bash
mw project get p-XXXXXX
```

Replace `p-XXXXXX` with the actual project ID.

**Expected output**: Project details (name, description, status)

**If access denied**: Token may lack permissions or project ID is incorrect.

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
- ✅ API token configured and valid
- ✅ Project ID identified (either in context or ready to pass explicitly)
- ✅ Project is accessible with current token
- ✅ User is in the correct application directory

---

## Common Issues

### Issue: "Authentication failed"

**Cause**: Token expired or invalid  
**Solution**: Generate a new API token in mStudio and update context

### Issue: "Project not found"

**Cause**: Wrong project ID or insufficient permissions  
**Solution**: Verify project ID with `mw project list` and check token permissions

### Issue: "CLI command not found"

**Cause**: CLI not in PATH or not installed  
**Solution**: Reinstall CLI or check PATH configuration

---

## Next Step

Once all checks pass, proceed to **02-cli-deploy-local.md** to test the deployment.
