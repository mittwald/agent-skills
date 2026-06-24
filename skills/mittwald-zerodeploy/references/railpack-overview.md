# Railpack Overview

**Railpack** is the build inference engine used by mittwald's zerodeploy workflow. It automatically detects project types and generates build plans using Cloud Native Buildpacks.

---

## What is Railpack?

Railpack analyzes your project structure and selects appropriate buildpacks to:
1. **Detect** the programming language and framework
2. **Install** dependencies (npm, pip, composer, etc.)
3. **Build** the application if necessary (compile, bundle, etc.)
4. **Package** everything into a container image
5. **Configure** the runtime environment

**No Dockerfile needed** - Railpack figures out what to do automatically.

---

## Official Documentation

**Railpack Getting Started**: https://railpack.com/getting-started

Review this for:
- Detailed buildpack behavior
- Advanced configuration options
- Troubleshooting specific detection issues

---

## Supported Languages & Frameworks

Railpack supports the most common web development stacks:

### JavaScript/Node.js
- ✅ **Express**, Koa, Fastify (Node.js servers)
- ✅ **Next.js**, Nuxt.js (full-stack frameworks)
- ✅ **React**, Vue, Angular (static builds via npm/yarn)
- ✅ npm, yarn, pnpm (package managers)
- ✅ TypeScript (via `tsconfig.json`)

**Detection**: Looks for `package.json`

### Python
- ✅ **Flask**, Django, FastAPI (web frameworks)
- ✅ pip, pipenv, poetry (dependency management)
- ✅ requirements.txt, Pipfile, pyproject.toml
- ✅ Python 3.8+

**Detection**: Looks for `requirements.txt`, `Pipfile`, or `pyproject.toml`

### PHP
- ✅ **Laravel**, Symfony, WordPress (frameworks/CMS)
- ✅ Composer (dependency management)
- ✅ PHP 7.4, 8.0, 8.1, 8.2

**Detection**: Looks for `composer.json`

### Ruby
- ✅ **Rails**, Sinatra (web frameworks)
- ✅ Bundler (dependency management)
- ✅ Ruby 2.7, 3.0, 3.1, 3.2

**Detection**: Looks for `Gemfile`

### Go
- ✅ Standard Go modules
- ✅ Go 1.19+

**Detection**: Looks for `go.mod`

### Static Sites
- ✅ HTML/CSS/JavaScript (no build required)
- ✅ Static site generators (if they use supported package managers)

**Detection**: If no other buildpack matches, serves as static content

---

## How Detection Works

### Step 1: Analyze Project Root
Railpack scans the project root directory for key files:
- `package.json` → Node.js buildpack
- `requirements.txt` or `pyproject.toml` → Python buildpack
- `composer.json` → PHP buildpack
- `Gemfile` → Ruby buildpack
- `go.mod` → Go buildpack

### Step 2: Detect Framework
Within each language, Railpack may detect specific frameworks:
- Node.js: Checks for `next.config.js` (Next.js), `nuxt.config.js` (Nuxt), etc.
- Python: Checks for `manage.py` (Django), `app.py` or `wsgi.py` (Flask)
- PHP: Checks for `artisan` (Laravel), `bin/console` (Symfony)

### Step 3: Build Plan Generation
Railpack creates a build plan with phases:
1. **Install dependencies**: `npm install`, `pip install -r requirements.txt`, etc.
2. **Build if needed**: `npm run build` (for frameworks that need compilation)
3. **Configure runtime**: Set start command, expose ports, set environment

### Step 4: Execute Build
Cloud Native Buildpacks execute the plan in a containerized environment.

---

## When Railpack Fails to Detect

### No Buildpack Found
**Error**: `Could not detect project type` or `No buildpack found`

**Causes**:
- Missing key files (`package.json`, `requirements.txt`, etc.)
- Files not at project root (e.g., in a subdirectory)
- Unusual project structure

**Solutions**:
- Ensure key files are at project root
- For monorepos, deploy each service separately
- If detection still fails → escalate (see `when-to-escalate.md`)

### Multiple Buildpacks Conflict
**Error**: `Ambiguous project type` or similar

**Causes**:
- Multiple language indicators at root (e.g., both `package.json` and `requirements.txt`)
- Buildpacks can't determine which is primary

**Solutions**:
- Structure project so one language is clearly primary
- For multi-language projects → escalate

### Dependencies Can't Install
**Error**: `npm install failed` or `pip install failed`

**Causes**:
- Private packages not accessible (authentication needed)
- Package registry down or unreachable
- Incompatible versions specified

**Solutions**:
- Check if packages are public and accessible
- Verify version constraints in lockfiles
- If authentication needed for private packages → escalate

### Build Command Fails
**Error**: `npm run build failed` or similar

**Causes**:
- Missing build script in `package.json`
- Build requires environment variables not set
- Build requires system dependencies not in base image

**Solutions**:
- Ensure build scripts are defined and tested locally
- Pass required environment variables via `--env` or `--env-file`
- If system dependencies needed → escalate

---

## Dockerfile Bypass Behavior

**CRITICAL**: If a `Dockerfile` exists at project root, Railpack is **completely bypassed**.

The CLI and GitHub Action will:
1. Detect the Dockerfile
2. Use `docker build` with the Dockerfile
3. Ignore Railpack entirely

**This is why faulty Dockerfiles cause issues** - see `pitfalls.md` for details.

**To force Railpack usage**: Delete or rename the Dockerfile.

---

## Environment Variables

Railpack respects certain environment variables:

### Build-time variables
- `NODE_ENV`: Affects Node.js dependency installation (dev vs. prod)
- `NPM_CONFIG_PRODUCTION`: Controls npm behavior
- `PYTHON_VERSION`: Override detected Python version

XXX: Mention this:
https://railpack.com/config/environment-variables#build-configuration

### Runtime variables
- `PORT`: Most buildpacks configure apps to respect this for port binding
- `WEB_CONCURRENCY`: Number of workers for production servers

Pass these via `--env` or `--env-file` during deployment.

---

## Port Detection

Railpack buildpacks typically configure apps to listen on a port specified by the `PORT` environment variable.

**Default behavior**:
- Sets `PORT=8080` if not specified
- App should listen on `0.0.0.0:$PORT` (not `localhost`)

**If your app doesn't respect `PORT`**:
- Check logs to find actual port
- Reconfigure ingress in mStudio UI
- See `port-configuration.md` for details

---

## Customizing Railpack Behavior

### Project-level configuration

This is an advanced topic - see Railpack documentation for details.

---

## Comparison: Railpack vs. Custom Dockerfiles

| Feature | Railpack (Auto-detection) | Custom Dockerfile |
|---|---|---|
| **Setup effort** | None (auto-detects) | High (write and maintain) |
| **Expertise needed** | None | Docker knowledge required |
| **Maintenance** | Buildpacks auto-update | Must update manually |
| **Flexibility** | Limited to supported stacks | Full control |
| **Best for** | Standard web apps | Custom/exotic projects |
| **Failure risk** | Low (tested buildpacks) | High (human error) |

**Recommendation**: Use Railpack for standard projects, custom Dockerfiles only when necessary.

---

## Troubleshooting Railpack Issues

### Build logs show "nothing to detect"
- Key files missing or in wrong location
- Verify project structure matches expected patterns

### Build succeeds but app won't start
- Check runtime command configuration
- Verify app listens on correct port
- Review container logs in mStudio

### Build fails with cryptic errors
- May be hitting Railpack limits
- After 2-3 attempts → escalate (see `when-to-escalate.md`)

---

## Related References

- `pitfalls.md` - Faulty Dockerfile detection and port issues
- `when-to-escalate.md` - When Railpack can't handle your project
- `port-configuration.md` - How ports are configured in different frameworks
