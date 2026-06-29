# Secrets Management

**Critical principle**: Never commit secrets to version control. This guide covers how to handle API keys, database passwords, and other sensitive configuration in zerodeploy workflows.

---

## The Golden Rule

### ❌ NEVER do this

```bash
# .env file committed to git
DATABASE_URL=mysql://user:password@host/db
API_KEY=sk-1234567890abcdef
APP_SECRET=super-secret-value
```

### ✅ ALWAYS do this

```bash
# .env file in .gitignore
# Values stored in deployment tools (CLI flags, GitHub Secrets, mStudio UI)
```

---

## Security Best Practices

### 1. Keep secrets out of version control

- **Add `.env` to `.gitignore`**
- Never commit API keys, passwords, or tokens
- Use `.env.example` for documentation (with fake values)

### 2. Different secrets for different environments

- **Development**: Use test/sandbox credentials
- **Production**: Use real credentials with limited permissions
- Never use production secrets in development

### 3. Principle of least privilege

- Grant minimum necessary permissions to tokens/keys
- Use separate credentials per service when possible
- Rotate secrets regularly

### 4. Encrypt secrets at rest

- GitHub Secrets are encrypted automatically
- mStudio stores environment variables securely
- Local `.env` files are not encrypted (keep them out of git!)

---

## For CLI Deployments

### Option A: Environment file (recommended for many secrets)

**Create `.env` file** (locally, not in git):

```bash
# .env
DATABASE_URL=mysql://user:password@host/db
API_KEY=sk-1234567890abcdef
APP_SECRET=super-secret-value
SMTP_PASSWORD=email-password
```

**Deploy with env file**:

```bash
mw experimental deploy --wait \
  --env-file .env \
  --project-id p-xxxxxx
```

### Option B: Pass via command line (for few secrets)

**Deploy with inline env vars**:

```bash
mw experimental deploy --wait \
  --env APP_ENV=production \
  --env API_KEY=sk-1234567890abcdef \
  --project-id p-xxxxxx
```

**⚠️ Warning**: Command-line arguments may be visible in:

- Shell history (`~/.bash_history`, `~/.zsh_history`)
- Process lists (`ps aux`)

For sensitive secrets, prefer `--env-file`.

### Option C: Load from password manager

**Use tools like 1Password CLI, pass, etc.**:

```bash
export DATABASE_URL=$(op read "op://vault/db-credentials/url")
export API_KEY=$(op read "op://vault/api-keys/production")

mw experimental deploy --wait \
  --env DATABASE_URL="$DATABASE_URL" \
  --env API_KEY="$API_KEY" \
  --project-id p-xxxxxx
```

---

## For GitHub Actions Deployments

### Step 1: Configure GitHub Secrets

Navigate to: `Repository → Settings → Secrets and variables → Actions`

**Click**: "New repository secret"

**Add each secret**:

- Name: `DATABASE_URL`
- Value: `mysql://user:password@host/db`

**Repeat for all secrets**:

- `API_KEY`
- `APP_SECRET`
- `SMTP_PASSWORD`
- etc.

### Step 2: Pass secrets to deployment

**Option A: Create .env file in workflow** (recommended)

```yaml
- name: Create .env for deployment
  run: |
    {
      echo "APP_ENV=production"
      echo "DATABASE_URL=${{ secrets.DATABASE_URL }}"
      echo "API_KEY=${{ secrets.API_KEY }}"
      echo "APP_SECRET=${{ secrets.APP_SECRET }}"
      echo "SMTP_PASSWORD=${{ secrets.SMTP_PASSWORD }}"
    } > .env

- name: Deploy with zerodeploy
  uses: mittwald/zerodeploy-action@v1
  with:
    mittwald-api-token: ${{ secrets.MITTWALD_API_TOKEN }}
    mittwald-project-id: ${{ secrets.MITTWALD_PROJECT_ID }}
```

The action automatically looks for `.env` at `$GITHUB_WORKSPACE/.env`.

**Option B: Pass via action inputs** (if supported)

Check `mittwald/zerodeploy-action` documentation for environment variable inputs.

### Step 3: Verify secrets are applied

**Check workflow logs**:

- GitHub automatically masks secret values in logs
- You'll see `***` instead of actual values

**Check deployment**:

- Test app functionality that depends on secrets
- Review container logs in mStudio (secrets should not be logged!)

---

## For mStudio UI (Post-Deployment)

### Editing environment variables after deployment

**Sometimes you need to update secrets without redeploying**:

1. **Navigate to**: mStudio → Projects → [Your Project] → Containers
2. **Select your container**
3. **Go to**: Environment Variables tab
4. **Add or edit variables**:
   - Click "Add Variable"
   - Name: `DATABASE_URL`
   - Value: `mysql://user:password@host/db`
5. **Save changes**
6. **Container restarts automatically** with new variables

**Use cases**:

- Quick fixes (wrong password, typo in URL)
- Rotating credentials
- Testing different configuration values
- Debugging environment-specific issues

---

## .gitignore Configuration

**Always include**:

```gitignore
# Environment files
.env
.env.local
.env.production
.env.development
.env.test

# Backup files that might contain secrets
*.env.backup
.env.*

# IDE/editor files (may cache env vars)
.vscode/settings.json
.idea/workspace.xml
```

**Recommended: Include .env.example**:

```bash
# .env.example (safe to commit - no real values!)
DATABASE_URL=mysql://user:password@localhost/dbname
API_KEY=your-api-key-here
APP_SECRET=generate-a-secret-key
SMTP_PASSWORD=your-smtp-password
```

Developers can copy `.env.example` to `.env` and fill in real values locally.

---

## Common Mistakes

### Mistake #1: Committing .env files

**How it happens**:

- Forgetting to add `.env` to `.gitignore`
- Using `git add .` without checking
- IDE auto-adding files to git

**How to fix**:

```bash
# Remove from git but keep local file
git rm --cached .env
echo ".env" >> .gitignore
git add .gitignore
git commit -m "Remove .env from git, add to .gitignore"
git push
```

**If already pushed**:

- **Rotate all secrets immediately** (treat as compromised)
- Consider using `git-filter-repo` or `BFG Repo-Cleaner` to purge history
- Inform your team

### Mistake #2: Hardcoding secrets in code

**Bad**:

```javascript
// ❌ NEVER do this
const apiKey = 'sk-1234567890abcdef';
const dbPassword = 'super-secret-password';
```

**Good**:

```javascript
// ✅ Read from environment variables
const apiKey = process.env.API_KEY;
const dbPassword = process.env.DB_PASSWORD;

if (!apiKey || !dbPassword) {
  throw new Error('Missing required environment variables');
}
```

### Mistake #3: Logging secrets

**Bad**:

```javascript
console.log('Connecting with password:', password);
console.log('Full database URL:', process.env.DATABASE_URL);
```

**Good**:

```javascript
console.log('Connecting to database...');
console.log('Database host:', new URL(process.env.DATABASE_URL).host);
// Log only non-sensitive parts
```

### Mistake #4: Sharing secrets insecurely

**Bad**:

- Sending passwords via email or chat
- Pasting secrets in Slack/Discord
- Storing in shared Google Docs

**Good**:

- Use password managers with sharing features (1Password, Bitwarden)
- Use encrypted secret-sharing services (Mozilla Send alternatives)
- Store in secure vaults (HashiCorp Vault, AWS Secrets Manager)

---

## Secret Rotation

**When to rotate secrets**:

- **Immediately**: If secrets were committed to git or exposed publicly
- **Soon**: If someone with access left the team
- **Regularly**: Every 90 days as a best practice

**How to rotate without downtime**:

1. **Generate new secret** (new API key, new password)
2. **Add new secret alongside old** (both active)
3. **Update deployment** to use new secret
4. **Verify app works** with new secret
5. **Revoke old secret** after confirmation

---

## Validating Secrets Are Applied

### Method 1: Test functionality

- Try feature that uses the secret (database query, API call)
- If it works, secret is applied correctly

### Method 2: Check logs for errors

- Navigate to: mStudio → Container → Logs
- Look for:
  - ✅ `Connected to database successfully`
  - ❌ `Authentication failed: invalid credentials`

---

## Framework-Specific Patterns

### Node.js (Express, Next.js, etc.)

**Use `dotenv` package** (for local development):

```bash
npm install dotenv
```

```javascript
// Load at app startup (local dev only - not needed in deployment)
if (process.env.NODE_ENV !== 'production') {
  require('dotenv').config();
}

// Access vars
const dbUrl = process.env.DATABASE_URL;
```

### Python (Flask, Django, FastAPI)

**Use `python-dotenv`** (for local development):

```bash
pip install python-dotenv
```

```python
# Load at startup (local dev)
from dotenv import load_dotenv
load_dotenv()

# Access vars
import os
db_url = os.getenv('DATABASE_URL')
```

### PHP (Laravel, Symfony)

**Laravel**:

```php
// .env file automatically loaded by Laravel
$dbUrl = env('DATABASE_URL');
```

**Plain PHP**:

```php
// Use vlucas/phpdotenv
require 'vendor/autoload.php';
$dotenv = Dotenv\Dotenv::createImmutable(__DIR__);
$dotenv->load();

$dbUrl = $_ENV['DATABASE_URL'];
```

---

## Related References

- `pitfalls.md` - Security mistakes to avoid
- Playbook `02-cli-deploy-local.md` - Using --env and --env-file
- Playbook `03-setup-github-action.md` - Configuring GitHub Secrets
