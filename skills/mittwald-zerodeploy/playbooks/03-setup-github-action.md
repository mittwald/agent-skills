# Playbook: Setup GitHub Action

**Goal**: Automate deployment using GitHub Actions after successful local testing with the CLI.

**Prerequisites**:

- ✅ Local deployment via `mw experimental deploy` works
- ✅ User has GitHub repository for the project
- ✅ User has API token from mStudio

---

## Step 1: Configure GitHub Secrets

### Required secrets

Navigate to: `Repository Settings → Secrets and variables → Actions → New repository secret`

**1. MITTWALD_API_TOKEN**

- Value: The API token from mStudio
- Same token used for local CLI authentication
- See: https://developer.mittwald.de/docs/v2/api/intro/#obtaining-an-api-token

**2. MITTWALD_PROJECT_ID**

- Value: Your project ID (e.g., `p-abc123`)
- Same project ID used in local testing
- Can be found in mStudio URL or via `mw context get`

### Optional secrets (if your app needs them)

**APP_SECRET, DATABASE_PASSWORD, API_KEYS, etc.**

- Any runtime secrets your application needs
- Will be passed to the container via `.env` file generation in workflow

---

## Step 2: Create Workflow File

Create `.github/workflows/zerodeploy.yml` in your repository:

```yaml
name: Deploy to mittwald Container Hosting

on:
  workflow_dispatch:  # Manual trigger for testing
  push:
    branches:
      - main  # Auto-deploy on push to main (optional)

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      # Optional: Create .env file if your app needs runtime secrets
      - name: Create .env for deployment
        run: |
          {
            echo "APP_ENV=production"
            echo "APP_SECRET=${{ secrets.APP_SECRET }}"
            echo "DATABASE_URL=${{ secrets.DATABASE_URL }}"
          } > .env
      
      - name: Deploy with zerodeploy
        uses: mittwald/zerodeploy-action@v1
        with:
          mittwald-api-token: ${{ secrets.MITTWALD_API_TOKEN }}
          mittwald-project-id: ${{ secrets.MITTWALD_PROJECT_ID }}
```

**Notes**:

- The `.env` file step is **optional** - only needed if your app requires runtime secrets
- The action automatically looks for `.env` in `$GITHUB_WORKSPACE/.env`
- Remove the `push.branches` trigger if you only want manual deploys initially

---

## Step 3: Commit and Push

```bash
git add .github/workflows/zerodeploy.yml
git commit -m "Add mittwald deployment workflow"
git push origin main
```

**Important**: Do NOT commit `.env` files to the repository! Only create them dynamically in the workflow.

---

## Step 4: Test Manual Deployment

### Trigger the workflow manually

1. Go to: `Repository → Actions tab`
2. Select: "Deploy to mittwald Container Hosting"
3. Click: "Run workflow" → "Run workflow"

### Monitor the workflow

Watch the workflow run in real-time:

- **Checkout repository**: Should complete quickly
- **Create .env**: Only runs if you included this step
- **Deploy with zerodeploy**: Main deployment step (may take 2-5 minutes)

---

## Step 5: Verify Deployment

After the workflow completes:

1. **Check workflow status**: Should show green checkmark
2. **Expand deploy step**: Look for deployment URL in logs
3. **Load** `05-verify.md` to test the deployed application

---

## Workflow Variations

### Auto-deploy on every push

Keep this in the `on:` section:

```yaml
on:
  push:
    branches:
      - main
```

### Auto-deploy on tags only

```yaml
on:
  push:
    tags:
      - 'v*'
```

### Custom domain prefix

Add to the `mittwald/zerodeploy-action` `with:` section:

```yaml
with:
  mittwald-api-token: ${{ secrets.MITTWALD_API_TOKEN }}
  mittwald-project-id: ${{ secrets.MITTWALD_PROJECT_ID }}
  uri-prefix: myapp  # Custom prefix instead of 'webapp'
```

---

## Common Issues

### "Authentication failed"

- Check `MITTWALD_API_TOKEN` secret is set correctly
- Token may have expired → regenerate in mStudio

### "Project not found"

- Check `MITTWALD_PROJECT_ID` secret matches your project
- Verify the format: `p-xxxxxx`

### "Build failed in GitHub Actions but works locally"

- Check if `.env` file is needed but not created in workflow
- Verify all required secrets are configured in GitHub
- Check GitHub Actions runner has necessary build tools

### "Deployment succeeds but app doesn't work"

- Environment variables may be missing or incorrect
- Check the `.env` file creation step in workflow
- Verify secrets in GitHub match what the app expects

### Workflow doesn't appear in Actions tab

- Ensure workflow file is in `.github/workflows/` directory
- Filename must end in `.yml` or `.yaml`
- File must be pushed to the repository (default branch)

---

## Security Best Practices

✅ **DO**:

- Store API tokens in GitHub Secrets
- Create `.env` files dynamically in workflow
- Use `workflow_dispatch` for manual testing first
- Limit secret access to specific workflows if possible

❌ **DON'T**:

- Commit API tokens or secrets to the repository
- Commit `.env` files to git
- Print secret values in workflow logs
- Use secrets in pull requests from forks (they're not available)

See `references/secrets-management.md` for detailed guidance.

---

## Next Steps

### After successful workflow run

1. **Load** `05-verify.md` to test the deployment
2. **Monitor subsequent runs** to ensure consistency
3. **Optional**: Set up deployment notifications (Slack, Discord, email)

### If workflow fails

1. **Check workflow logs** for specific error messages
2. **Load** `04-troubleshoot-deployment.md` for debugging guidance
3. **Compare with local deployment** - did local CLI work but GitHub Actions fail?
