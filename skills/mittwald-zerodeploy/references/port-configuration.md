# Port Configuration

Port handling is one of the most common sources of deployment issues. This reference explains how ports work in containerized apps and how to fix port-related problems.

---

## The Port Problem

**Symptom**: Deployment succeeds, container runs, but app is not accessible (502 Bad Gateway).

**Root cause**: The application listens on a port that doesn't match what the ingress expects.

---

## How Port Mapping Works

### In traditional hosting

- App listens on a port (e.g., 3000)
- You access it directly: `http://localhost:3000`

### In container hosting

- App listens on a port **inside** the container (e.g., 8080)
- **Ingress** maps external requests to that internal port
- You access it via: `https://webapp.p-xxxxxx.project.space`

**If the mapping is wrong, ingress can't reach your app** → 502 error.

---

## Default Port Expectations

Most frameworks have conventional default ports:

| Framework | Default Port | Configurable? |
|---|---|---|
| **Node.js/Express** | 3000, 8080 | ✅ Via `PORT` env var |
| **Next.js** | 3000 | ✅ Via `-p` flag or `PORT` |
| **Create React App (dev)** | 3000 | ⚠️ Not used in production (static files) |
| **Angular CLI (dev)** | 4200 | ⚠️ Not used in production (static files) |
| **Vue/Vite (dev)** | 5173 | ⚠️ Not used in production (static files) |
| **Python/Flask** | 5000 | ✅ Via `app.run(port=...)` |
| **Python/Django** | 8000 | ✅ Via `manage.py runserver 0.0.0.0:PORT` |
| **Python/FastAPI** | 8000 | ✅ Via uvicorn `--port` |
| **PHP/Laravel** | 8000 | ✅ Via `php artisan serve --port=...` |
| **Ruby/Rails** | 3000 | ✅ Via `-p` flag or `PORT` env var |
| **Go (net/http)** | 8080 | ✅ Depends on code implementation |

---

## The PORT Environment Variable

**Best practice**: Make your app respect the `PORT` environment variable.

### Why?

- **Flexibility**: Change port without modifying code
- **Compatibility**: Works with buildpacks, Docker, PaaS platforms
- **Standardization**: Common convention across languages

### Implementation Examples

**Node.js/Express**:

```javascript
const express = require('express');
const app = express();

// Use PORT env var, fallback to 3000
const port = process.env.PORT || 3000;

app.listen(port, '0.0.0.0', () => {
  console.log(`Server listening on port ${port}`);
});
```

**Python/Flask**:

```python
import os
from flask import Flask

app = Flask(__name__)

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)
```

**Python/Django** (use environment in settings):

```python
# In manage.py or wsgi.py
import os
port = int(os.environ.get('PORT', 8000))
# Pass to runserver or uvicorn
```

**Go**:

```go
package main

import (
    "fmt"
    "net/http"
    "os"
)

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    http.HandleFunc("/", handler)
    fmt.Printf("Listening on port %s\n", port)
    http.ListenAndServe(":"+port, nil)
}
```

**PHP (using built-in server)**:

```bash
php -S 0.0.0.0:${PORT:-8000}
```

---

## Detecting the Actual Port

If your app doesn't respond on the expected port, **check the logs**:

### In mStudio UI

1. Navigate to: `mStudio → Projects → [Your Project] → Containers`
2. Find your container (search by URL prefix)
3. Click on container → **Logs** tab
4. Look for startup messages like:
   - `Listening on port 4200`
   - `Server running at http://0.0.0.0:9000`
   - `Started on :8081`

### Example log patterns

**Express**:

```
Server listening on port 3000
Server running at http://0.0.0.0:3000
```

**Flask**:

```
* Running on http://0.0.0.0:5000
* Debug mode: off
```

**Django**:

```
Starting development server at http://0.0.0.0:8000/
Quit the server with CONTROL-C.
```

**Rails**:

```
=> Booting Puma
=> Rails 7.0.0 application starting in production
* Listening on http://0.0.0.0:3000
```

---

## Fixing Port Mismatches

### Solution 1: Reconfigure Ingress in mStudio (Recommended)

**When to use**: Port is hardcoded or difficult to change in app code.

**Steps**:

1. Let deployment complete (even if app isn't accessible)
2. Check logs to find actual port
3. Navigate to: `Container → Ports` tab in mStudio
4. **Edit port mapping**:
   - Example: Change `HTTP → 8080` to `HTTP → 4200`
5. Save changes
6. Container restarts automatically
7. Adjust ingress to new port mapping if needed
8. Test URL again

**Advantages**:

- ✅ No code changes needed
- ✅ No redeployment needed
- ✅ Works even for hardcoded ports

### Solution 2: Pass PORT Environment Variable

**When to use**: App respects `PORT` env var (recommended pattern).

**CLI deployment**:

```bash
mw experimental deploy --wait \
  --env PORT=8080 \
  --project-id p-xxxxxx
```

**GitHub Actions**:

```yaml
- name: Create .env for deployment
  run: |
    {
      echo "PORT=8080"
      echo "APP_ENV=production"
    } > .env

- name: Deploy with zerodeploy
  uses: mittwald/zerodeploy-action@v1
  with:
    mittwald-api-token: ${{ secrets.MITTWALD_API_TOKEN }}
    mittwald-project-id: ${{ secrets.MITTWALD_PROJECT_ID }}
```

**Advantages**:

- ✅ Standardizes port across environments
- ✅ Works with Railpack's expectations
- ✅ Better for infrastructure-as-code

### Solution 3: Modify Application Code

**When to use**: For new projects or if you have flexibility to change code.

**Make the app respect PORT env var** (see examples above in "The PORT Environment Variable" section).

**Advantages**:

- ✅ Most flexible long-term
- ✅ Portable across different hosting platforms
- ✅ Following best practices

---

## Listening on the Right Interface

**Critical**: Apps must listen on `0.0.0.0`, not `localhost` or `127.0.0.1`.

### Why?

- **`0.0.0.0`**: Listens on all network interfaces (container networking works)
- **`localhost` / `127.0.0.1`**: Only listens on loopback (ingress can't reach it)

### Examples of WRONG configuration

**Node.js (bad)**:

```javascript
app.listen(3000, 'localhost');  // ❌ Won't work in container
app.listen(3000, '127.0.0.1'); // ❌ Won't work in container
```

**Python (bad)**:

```python
app.run(host='localhost', port=5000)  # ❌ Won't work
app.run(host='127.0.0.1', port=5000)  # ❌ Won't work
```

### Examples of CORRECT configuration

**Node.js (good)**:

```javascript
app.listen(3000, '0.0.0.0');  // ✅ Works
app.listen(3000);             // ✅ Usually defaults to 0.0.0.0
```

**Python (good)**:

```python
app.run(host='0.0.0.0', port=5000)  # ✅ Works
```

---

## Framework-Specific Quirks

### Angular CLI (Development Server)

**Problem**: Angular dev server (`ng serve`) is not for production use.

**Solution**: Use `ng build` to create static files, then serve with a static file server:

```dockerfile
# This is handled by Railpack automatically
# Just ensure package.json has:
{
  "scripts": {
    "build": "ng build --configuration production"
  }
}
```

Railpack will build static files and serve them (no port config needed).

### Next.js

**Default**: Listens on port 3000, respects `PORT` env var.

**Start command**:

```json
{
  "scripts": {
    "start": "next start -p ${PORT:-3000}"
  }
}
```

Or rely on Next.js respecting `PORT`:

```bash
PORT=8080 npm start
```

### Create React App

**Production**: Builds static files (`npm run build`) that are served by a static file server.

**No port configuration needed** - Railpack handles serving the built files.

### Django with Gunicorn

**For production Django**, use Gunicorn or uvicorn:

```bash
gunicorn myproject.wsgi:application --bind 0.0.0.0:${PORT:-8000}
```

**Or with environment variable**:

```python
# In Procfile or start script
import os
port = os.environ.get('PORT', '8000')
# Pass to gunicorn via --bind
```

### Laravel with Octane

**Laravel Octane** (for high-performance Laravel):

```bash
php artisan octane:start --port=${PORT:-8000} --host=0.0.0.0
```

---

## Multiple Ports / Complex Services

**Symptom**: App needs multiple ports (e.g., HTTP + WebSocket, HTTP + gRPC).

**Example scenarios**:

- Main HTTP on port 8080
- WebSocket on port 8081
- Admin panel on port 9000

### Solution: Switch use case

This is an advanced use case. If your project requires complex port mappings, consider whether zerodeploy is the right tool or if you need `deploy-container-action` with explicit configuration.

---

## Troubleshooting Port Issues

### Issue: 502 Bad Gateway

**Diagnosis**:

1. Check container logs for port binding message
2. Note the port the app is listening on
3. Compare with ingress configuration in mStudio

**Fix**:

- Reconfigure ingress to match actual port
- Or pass `PORT` env var to standardize

### Issue: Connection Refused

**Diagnosis**:

- Container may not be running
- App may have crashed on startup

**Fix**:

1. Check container status in mStudio (should be "Running")
2. Review logs for crash errors
3. If crash-looping, fix the underlying error (see `04-troubleshoot-deployment.md`)

### Issue: Port Already in Use (Rare)

**Error in logs**:

```
Error: listen EADDRINUSE: address already in use :::8080
```

**This is very rare in containerized environments** (each container has isolated networking).

**If it happens**:

- May indicate misconfiguration in app startup
- Check if app is trying to start multiple servers on the same port

---

## Testing Port Configuration Locally

**Before deploying**, test locally:

### Node.js

```bash
PORT=8080 npm start
curl http://localhost:8080
```

### Python

```bash
PORT=8080 python app.py
curl http://localhost:8080
```

### Ensure app responds** on the configured port

---

## Related References

- `pitfalls.md` - Gotcha #2: Hidden Port Configurations
- Playbook `04-troubleshoot-deployment.md` - Debugging 502 errors
- `railpack-overview.md` - How Railpack configures ports
