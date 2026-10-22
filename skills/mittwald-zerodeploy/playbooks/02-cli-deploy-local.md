# Playbook: CLI Deploy (Local)

**Goal**: Deploy the application from the user's local machine using `mw experimental deploy` to validate the build before setting up automation.

**Prerequisite**: The target project was explicitly confirmed by the user in `01-provision-target.md`. Do not continue without that confirmation.

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

Check if a Dockerfile exists:

```bash
ls -la Dockerfile docker-compose.yml
```

**If a Dockerfile exists**:

- It is used as-is and Railpack is skipped
- Note the `EXPOSE` port(s) and the port the app listens on (e.g. `ENV PORT=3000`). If the exposed port is not `80`, you **must** pass `--env PORT=<exposed port>` (see [Port handling](#port-handling))
- Don't delete a Dockerfile up front. Only consider deleting it if the **build** fails because of it (see `references/pitfalls.md`)

### 3. Choose names (don't rely on the defaults)

Derive **one** name from the application and use it for all three naming flags:

- Source, in this order: `name` in `package.json` / `pyproject.toml` / `composer.json`, the Go module's last path segment, else the directory name
- Normalize: lowercase, only `a-z`, `0-9` and `-` (e.g. `@acme/Works_On_My_Machine` → `works-on-my-machine`)

| Flag | CLI default | Risk of the default |
|---|---|---|
| `--uri-prefix` | `webapp` | If `webapp.<short-id>.project.space` already exists in the project, the CLI prints `Reusing existing domain…` and **points that hostname at your container** |
| `--service-name` | `app-<project-id>` | Every unnamed deploy into the project replaces the same service |
| `--image-name` | `app-image` | Every unnamed deploy overwrites the same image tag in the project registry |

If the target is an existing project, check the chosen name against `mittwald_domain_virtualhost_list` and `mittwald_container_list` first (see `01-provision-target.md`, Step 3c).

---

## Deploy

### Command

```bash
mw experimental deploy \
  --project-id p-xxxxxx \
  --uri-prefix my-app \
  --service-name my-app \
  --image-name my-app
```

Add `--env PORT=<port>` when the Dockerfile exposes a port other than `80` (see next section).

### Port handling

`mw experimental deploy` (CLI 1.25.0) decides the ports like this:

- **Ingress target port**: `--env PORT` if given, else the first `EXPOSE` port of the Dockerfile, else `80` (always `80` for Railpack builds)
- **Container environment**: the CLI **always sets `PORT=80`** unless you pass `--env PORT=...`. This overrides an `ENV PORT=...` in the Dockerfile

So a Dockerfile with `ENV PORT=3000` + `EXPOSE 3000` deployed without `--env PORT=3000` ends up with the app listening on 80 while the ingress targets 3000 → **502**. Always pass `--env PORT=<exposed port>` for such Dockerfiles. Details: `references/port-configuration.md`.

### Running the command

- **Don't pipe the output** through `tail`, `head` or `grep`. The user then sees nothing until the command exits and will assume it hangs
- **Don't add `--wait`**. `mw experimental deploy` accepts the flag but ignores it; the command always waits until the service runs and the domain is ready (timeout: `--wait-timeout`, default 600s)
- **Tell the user what to expect**: build and push of a small app take seconds. The first deploy to a **new hostname** also waits for the TLS certificate, which is usually the longest step. Redeploys to an existing hostname skip that wait

### Expected output (interactive terminal)

```
  ✅ Pushing docker image .... done
  💡 Pushed image registry.p-kpbj8e.project.space/my-app:latest to registry
  ✅ Deploying .... done
  💡 Service my-app is now running
Creating new domain for hostname "my-app.p-kpbj8e.project.space"
  ✅ Setting up domain .... done

  ┌──────────────────────────────────────────────────────────────────────────────┐
  │  SUCCESS                                                                     │
  │  Container 313b5da8-2899-41f4-bac9-02881969a59c was successfully deployed    │
  └──────────────────────────────────────────────────────────────────────────────┘

```

The URL is `https://<uri-prefix>.<short-id>.project.space`; you already know it from the flags.

### Expected output (non-interactive shell, e.g. agent tool calls)

Without a TTY the CLI prints one line per step and ends with:

```
Completed: Process completed successfully

Summary: [Complex content]
```

`[Complex content]` is a rendering bug of the CLI's plain-text renderer, not an error. Exit code `0` plus `Completed: Process completed successfully` means success.

If you see `Reusing existing domain for hostname …` on a **first** deploy, the hostname already existed in the project and now points at the new container. Stop and tell the user.

### Poll the app

The domain is ready when the command returns, but the app may still be starting. Poll it in a short loop until the **app** answers.

**Which path**: use `/` unless you found a health endpoint in the app's code (e.g. a route like `/health`, `/healthz` or `/up`). Don't guess one.

**When to stop**: any response that comes from the app counts, including `404`, `401` or a redirect (an API-only app may not serve `/` at all). Only `000` (no connection) and `502`/`503`/`504` (proxy can't reach the app yet) mean "not ready":

```bash
URL=https://my-app.p-xxxxxx.project.space/
for i in $(seq 1 12); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$URL")
  echo "attempt $i: $code"
  case "$code" in 000|502|503|504) sleep 5 ;; *) break ;; esac
done
```

- A `503` during the first seconds is normal
- A persistent `502` is almost always a port mismatch → `04-troubleshoot-deployment.md`
- Whether the response is the *right* one (e.g. `200` with the expected content) is checked in `05-verify.md`

---

## Deployment with Environment Variables

### Option A: Pass via command line

For a few variables:

```bash
mw experimental deploy \
  --project-id p-xxxxxx \
  --uri-prefix my-app --service-name my-app --image-name my-app \
  --env APP_ENV=production \
  --env API_KEY=sk-xxxxxx
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
mw experimental deploy \
  --project-id p-xxxxxx \
  --uri-prefix my-app --service-name my-app --image-name my-app \
  --env-file .env
```

**Security reminder**: Add `.env` to `.gitignore`! See `references/secrets-management.md`.

---

## Redeploying

Run the same command again with the **same** `--service-name` and `--uri-prefix`:

- The existing service is updated with the new image and environment and then recreated. It keeps its ID; no second service is left behind
- The existing domain is retargeted to the service (`Reusing existing domain…` is expected here)

A different `--service-name` creates an additional service next to the old one.

---

## Parsing Output

### Success indicators

- Exit code: `0`
- Message: "Container XYZ was successfully deployed" (TTY) or "Completed: Process completed successfully" (non-TTY)

### Failure indicators

- Exit code: non-zero
- `ERROR: Process failed: …` or error messages in output
- Build failed / Push failed / Deployment failed

### Harmless warnings

- `WARNING! Using --password via the CLI is insecure.` comes from the CLI's internal `docker login` call. Ignore it

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

### Deploy succeeds, URL returns 502

- Port mismatch between the app and the ingress, most often the `PORT=80` override described above
- Don't touch the Dockerfile; compare the port in the container log with the virtualhost's target port
- See `04-troubleshoot-deployment.md` and `references/port-configuration.md`

---

## Next Steps

### If deployment succeeds

1. **Note the deployment URL and service name**
2. **Proceed to** `05-verify.md` to test the deployment
3. After verification, proceed to `03-setup-github-action.md` for automation

### If deployment fails

1. **Check error message** in terminal output
2. **Load** `04-troubleshoot-deployment.md` for guidance
3. **Check** `references/pitfalls.md` for the 3 critical gotchas
4. If stuck after 2-3 attempts, load `references/when-to-escalate.md`
