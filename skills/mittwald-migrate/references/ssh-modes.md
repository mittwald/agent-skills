# SSH modes on Mittwald

Mittwald offers two SSH access modes per project. Choosing the right one is the most common newcomer trip — see Pitfall #3.

## Address format

Both modes share a common shape:

```
ssh <ssh-identity>@<short-id>@ssh.<cluster>.project.host
```

Where:

- `<ssh-identity>` is one of:
  - the **own studio user's full email address** (e.g. `dhermsmeier@codeboarder.de`) — note this contains an `@`, so the assembled URL has two `@` characters before the routing token
  - a **per-project ssh-user's `userName`** (e.g. `myproject-deploy`) — created via `ssh_user_create` / `mw ssh-user create`
- `<short-id>` is the routing token:
  - `a-XXXXX` → **Project-Host-SSH** (you land on the project host)
  - `c-XXXXX` → **Container-SSH** (you land inside the named container)
- `<cluster>` is the data center fragment, returned in the project object's `clusterId` field.

Both modes go through the same SSH gateway (`ssh.<cluster>.<clusterDomain>`).

> **Local SSH multiplexing breaks mStudio connections.** If your `~/.ssh/config` enables connection sharing (`ControlMaster auto` with a `ControlPath`), an mStudio connection can fail with a misleading `could not connect to project` even though the key is registered and the app is `ready` — the shared control socket is keyed on the gateway host and collides with the multi-`@` routing identity. Disable it per connection:
>
> ```
> ssh -o ControlMaster=no -o ControlPath=none <ssh-identity>@<short-id>@ssh.<cluster>.project.host
> ```
>
> Apply the same two flags to any `scp` / `rsync -e ssh` / `tar … | ssh …` pipeline against mStudio.

## Two SSH user models — which one are you using?

This decides where the SSH key lives and what the `<ssh-identity>` looks like in the URL.

### Model 1: own studio user (most common)

Your studio account itself is the SSH identity. The `<ssh-identity>` in the URL is your account's **full email address**.

- **Identity in SSH URL**: the email (e.g. `dhermsmeier@codeboarder.de`)
- **Where to register keys**: either the Studio UI at <https://studio.mittwald.de/app/profile/ssh-keys> (convenient for humans), or via the API — `GET /v2/users/self/ssh-keys` lists, `POST` the same path adds a key. Keys are scoped to your user across all projects/customers you have access to.
- **API gotcha**: managing keys via API requires a token with **`api_write`** (or a sufficiently scoped fine-grained token). A read-only token (`api_read`) returns `403` on these endpoints — that's a scope issue, not "the endpoint isn't available". See Pitfall #21.
- **When to use**: interactive operator work, anything where a human is at the keyboard. Default for this skill.

### Model 2: per-project ssh-user

A separate user scoped to **one project**. Has its own `userName` (independent of any email), and keys/password are managed via the API.

- **Identity in SSH URL**: the `userName` from the ssh-user record (no `@`)
- **Where to register keys**: via the API/CLI/MCP — `mw ssh-user create -p <projectId> --description "<reason>" --public-key '<ssh-rsa …>'` (or `mcp__mittwald__mittwald_ssh_user_create`).
- **API to list/manage**: `GET /v2/projects/{projectId}/ssh-users`, plus the `ssh_user_*` MCP tools and `mw ssh-user *` CLI subcommands.
- **When to use**: CI/CD, automation, service accounts, scoped least-privilege access. Recommended whenever a non-human will SSH in.

If the project's ssh-users list is empty (`GET /v2/projects/{id}/ssh-users` returns `[]`), the operator is using Model 1 — that's expected, not a missing setup.

## Project-Host-SSH (`a-XXXXX`)

What it is: a shell on the **project host** itself. The home directory is `/home/<p-shortId>/`. Two distinct areas matter (don't conflate them — Pitfall #4):

```
/home/<p-shortId>/
├── html/                  ← APP content: default web root for installed apps
├── <app-installation>/    ← APP content: an app installed at a custom installationPath
├── .config/php/           ← project-wide php.ini overrides (Pitfall §3a)
└── …
/files/
├── <app-shortname-1>/     ← STACK bind-mounts: what your compose YAML maps to
│   ├── postgres-dumps/
│   ├── uploads/
│   └── …
└── <app-shortname-2>/
```

- **Apps** (Managed Apps, PHP/Node/etc. runtime apps): content lives under the **project home**, at the app's `installationPath` — `/html` by default. Find the exact path via the project's `directories.Web` or the app installation's `installationPath`.
- **Container stacks**: bind-mounts live under **`/files/<app>/...`** — this is where bind-mounts in your compose YAML map to (Pitfall #4). Anything you write under `/files/...` becomes visible inside the matching container.

Mixing these up ("where are my WordPress files? `/files/` is empty!") is Pitfall #4.

Use it for:

- Landing DB dumps in transit (`ssh … 'cat > /files/myapp/postgres-dumps/dump.pgc'`)
- Writing file-transfer payloads (`tar … | ssh … 'tar -xf -'`)
- Inspecting state when a container is **stopped** (Container-SSH won't work — Container-SSH needs a running container)
- **Pre-loading data into a stopped stateful container** via its bind-mount path. If the project has no app installation yet (stack-only), install a dummy Static-Files app to obtain an `a-XXXXX` purely as the SSH anchor — see [`stateful-container-restore.md`](stateful-container-restore.md), Pitfall #19.
- Running tooling on the host (no, you can't `apt install` arbitrary things — it's a managed environment)

**Doesn't** give you access to:

- Named-volume contents (those live inside the container runtime)
- The container's runtime user / network namespace

## Container-SSH (`c-XXXXX`)

What it is: a shell **inside** a specific running container. The PID 1 is the container's main process; the filesystem is the container's filesystem (image + volumes); the network is the stack's internal network.

Use it for:

- Running `pg_restore`, `mysql` import, `php artisan migrate`, `rails console`, etc.
- Quick app-level introspection while debugging
- `chown -R` after a Project-Host-SSH-initiated file transfer (Pitfall #4 cleanup)

**Requires the container to be running.** `container_stop` makes Container-SSH unreachable. If the container is crash-looping, also unreachable — fix the boot before trying.

Each service in the stack has its **own** `c-XXXXX` short-ID. Find them via `mcp__mittwald__mittwald_container_list` or `_stack_ps`.

## Quick decision table

| Task | Mode |
|---|---|
| `pg_dump` from source straight onto Mittwald disk | Project-Host-SSH (target side) |
| `pg_restore` on Mittwald target | Container-SSH (postgresql container) |
| Drop+recreate target DB before restore | Container-SSH (postgresql container) |
| Copy uploads tree onto bind-mount | Project-Host-SSH |
| `chown` uploads tree to www-data | Container-SSH (app container) |
| Inspect a stopped container's data | Project-Host-SSH (via bind-mount path), or start the container first |
| Run a one-off app management command | Container-SSH (app container) |

## SSH user setup

Project-Host-SSH and Container-SSH share the project's SSH user list. Manage with:

```text
mcp__mittwald__mittwald_ssh_user_create
mcp__mittwald__mittwald_ssh_user_list
mcp__mittwald__mittwald_ssh_user_update
mcp__mittwald__mittwald_ssh_user_delete
```

The user's public SSH key authenticates against both modes. There's no separate "container user" concept at the SSH layer; the gateway routes based on the `a-XXXXX` / `c-XXXXX` token.

> **Readiness precondition.** SSH to a freshly-provisioned app only works once the app is `phase == "ready"` — the `a-XXXXX` routing and `/files/<app>/` tree don't exist while it's still `pending`/`installing`. Creating the ssh-user itself is near-instant, but it can't reach an app that isn't ready yet. Wait for readiness first (Pitfall #25; [`../playbooks/provision-target.md`](../playbooks/provision-target.md) §3a).

## Why this distinction matters

In a typical migration, **DB dump arrives via Project-Host-SSH** (landing on the bind-mount) and **DB restore runs via Container-SSH** (because `pg_restore` is a postgres client inside the postgres container). Mixing these up looks like "permission denied" or "command not found", and burns time on the wrong fix.

Always state explicitly in your status updates which mode you're using:

> Streaming dump via Project-Host-SSH (`a-laj9z8`) into `/files/myapp/postgres-dumps/`…
> Now connecting Container-SSH (`c-si8vdg`, postgresql service) to run pg_restore…

## Assembling the SSH command from API fields

There is **no single "give me the SSH command" endpoint**. `mw project ssh` and `mcp__mittwald__mittwald_project_ssh` compose the connection string from several fields. When driving via API only, you assemble it yourself.

Field sources (live-verified — see the worked example below):

| Field | What it is | API source |
|---|---|---|
| Gateway host | `ssh.<clusterId>.<clusterDomain>`, e.g. `ssh.fiestel.project.host` | `GET /v2/projects/{projectId}` → `clusterId` + `clusterDomain` |
| Project shortId (`p-XXXXX`) | for human reference / log lines (not in the address itself) | `GET /v2/projects/{projectId}` → `shortId` |
| Project home directory | `/home/p-XXXXX` — useful when composing paths from outside | `GET /v2/projects/{projectId}` → `directories.Home` |
| App installation shortId (`a-XXXXX`) | the routing token for **Project-Host-SSH** | `GET /v2/projects/{projectId}/app-installations` → `[].shortId` |
| Container shortId (`c-XXXXX`) | the routing token for **Container-SSH** | `GET /v2/projects/{projectId}/stacks` → `[].services[].shortId` |
| SSH identity — own studio user | full email address | `GET /v2/users/self` → `.email` |
| SSH identity — per-project ssh-user | the `userName` of the chosen ssh-user | `GET /v2/projects/{projectId}/ssh-users` → `[].userName` |

### Worked example (verified against `mw project ssh`)

Project `p-ia1rgw` (UUID `c5d48ee8-…`) on cluster `fiestel`, app installation `a-mdrqq5`, hypothetical postgresql container `c-b24c3b`. Operator's studio email `dhermsmeier@codeboarder.de`:

```text
Project-Host-SSH (write to /files/<app>/…):
  ssh dhermsmeier@codeboarder.de@a-mdrqq5@ssh.fiestel.project.host

Container-SSH (run pg_restore inside the postgresql service):
  ssh dhermsmeier@codeboarder.de@c-b24c3b@ssh.fiestel.project.host
```

Note the two `@` characters before the routing token — the first is **inside the email**, the second separates email from `a-XXXXX`/`c-XXXXX`. SSH parses this correctly because only the *last* `@` before the host is treated as the user/host separator.

If you need an `a-XXXXX` and the project doesn't have any app installations yet, see [`stateful-container-restore.md`](stateful-container-restore.md) — the "dummy app" pattern installs a minimal Static-Files app purely as an SSH anchor (Pitfall #19).

### Quick API recipe — own studio user (Model 1)

```bash
set -Eeuo pipefail

PROJ=<projectId>

# gateway from project object
read CLUSTER DOMAIN <<<"$(curl -sS -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  "https://api.mittwald.de/v2/projects/$PROJ" \
  | jq -r '"\(.clusterId) \(.clusterDomain)"')"
GATEWAY="ssh.$CLUSTER.$DOMAIN"

# app installation shortId for Project-Host-SSH (pick the right one if multiple)
A_ID=$(curl -sS -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  "https://api.mittwald.de/v2/projects/$PROJ/app-installations" \
  | jq -r '.[0].shortId')

# own studio user identity = email
SSH_IDENTITY=$(curl -sS -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  "https://api.mittwald.de/v2/users/self" | jq -r '.email')

echo "ssh $SSH_IDENTITY@$A_ID@$GATEWAY"
```

**Prerequisite for Model 1**: the operator's SSH **public key must already be registered** — either via the Studio UI at <https://studio.mittwald.de/app/profile/ssh-keys>, or `POST /v2/users/self/ssh-keys` with an `api_write` token. If SSH says "Permission denied (publickey)", that's where to look first. If the API call itself 403s instead of working, check token scope (Pitfall #21).

### Quick API recipe — per-project ssh-user (Model 2)

```bash
set -Eeuo pipefail

PROJ=<projectId>

# gateway + a-id same as above
read CLUSTER DOMAIN <<<"$(curl -sS -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  "https://api.mittwald.de/v2/projects/$PROJ" \
  | jq -r '"\(.clusterId) \(.clusterDomain)"')"
GATEWAY="ssh.$CLUSTER.$DOMAIN"
A_ID=$(curl -sS -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  "https://api.mittwald.de/v2/projects/$PROJ/app-installations" \
  | jq -r '.[0].shortId')

# per-project ssh-user
SSH_IDENTITY=$(curl -sS -H "Authorization: Bearer $MITTWALD_API_TOKEN" \
  "https://api.mittwald.de/v2/projects/$PROJ/ssh-users" \
  | jq -r '.[0].userName')   # if multiple, filter by description / id

echo "ssh $SSH_IDENTITY@$A_ID@$GATEWAY"
```

**Prerequisite for Model 2**: the ssh-user must already exist *and* have a key attached:

```bash
mw ssh-user create -p <projectId> \
  --description "ci-deploy" \
  --public-key "$(cat ~/.ssh/id_ed25519.pub)"
```

If `GET /v2/projects/{id}/ssh-users` returns `[]` and you intend to use Model 2, you haven't created one yet.

## Source-side SSH access (the other end)

Everything above is the **mittwald target**, which is always key-based. The **source** you're migrating from is arbitrary — classic shared hosting, a VPS, another hoster — and very often offers **only password SSH**, or presents an unknown host key on first connect. Both prompt interactively and will **stall a non-interactive (agent/CI) run** because there is no TTY to answer them (Pitfall #28). Make source SSH answer-free *before* piping a dump/copy through it:

- **Prefer `~/.ssh/config`.** If the operator already defined the host there (`Host src`, `HostName`, `User`, `IdentityFile`), a bare `ssh src` resolves everything and no secret touches the pipeline. Try this first.
- **Password auth** — pass the password via the `SSHPASS` env var, never in argv (argv is visible in `ps` and shell history):

  ```bash
  SSHPASS="$SRC_SSH_PW" sshpass -e ssh -o StrictHostKeyChecking=accept-new user@source 'mysqldump …'
  # matching rsync:
  SSHPASS="$SRC_SSH_PW" sshpass -e rsync -e 'ssh -o StrictHostKeyChecking=accept-new' user@source:/path/ ./local/
  ```

  `sshpass` isn't always present — `brew install sshpass` / `apt-get install sshpass`.
- **Key auth** — point at the key and skip the prompt: `ssh -i /path/to/key -o StrictHostKeyChecking=accept-new user@source '…'`. If the key material only lives in a secret store, write it to a temp file `chmod 600`, use it, then delete it.
- **`StrictHostKeyChecking=accept-new`** trusts a *new* host on first contact but still refuses a *changed* key (MITM protection intact). Use it for first-contact automation; don't downgrade to `no`.

### Pointing the mittwald `mw` SSH commands at a specific key/user

The SSH-tunnelling `mw` subcommands accept `--ssh-identity-file <path>` and `--ssh-user <name>`, or the env vars `MITTWALD_SSH_IDENTITY_FILE` and `MITTWALD_SSH_USER` — verified on `mw 1.19.0` for `mw app exec` and `mw database mysql import`/`dump` (check `--help` for others). Use these in headless/CI runs where the target key isn't the default `~/.ssh/id_*`, instead of editing `~/.ssh/config`.
