# Running the migration non-interactively (headless / CI)

This skill is **conversational by default** — it opens `AskUserQuestion` gates before every destructive or externally-visible step (see [`../SKILL.md`](../SKILL.md) "Confirmation gates"). When a human drives it, that's the safety model. When something *else* drives it — the Claude Agent SDK, `claude -p`, a CI job, or a UI wrapper — there is **nobody at the keyboard to answer**, and the run stalls at the first gate. This page is the contract for driving it headless without losing the safety intent.

## The rule: pre-decide, don't skip

Headless safety comes from **making every decision up front**, not from removing the gates. The gates still fire; the driving harness answers them from decisions the operator already made. Never run headless against resources the operator hasn't explicitly pre-authorized.

## 1. Pre-supply every decision in the initial prompt

The skill will otherwise ask for these — provide them so it doesn't have to:

- **Source**: type + coordinates (SSH host/user, kubeconfig context, compose path, or source mStudio project) and which app/installation(s) to move.
- **Target**: mStudio `projectId` (UUID) **and** `shortId`, and whether to reuse an existing project or create one.
- **Target app shape**: managed app vs runtime app vs container stack, plus the app version (the skill still diffs against the live catalog — [`app-catalog.md`](app-catalog.md)).
- **DB target**: managed MySQL vs container (mirror the source engine by default — [`database-engines.md`](database-engines.md)).
- **Domain plan**: which hostname(s) cut over, and that DNS is *not* to be changed automatically (the skill never touches registrars).

## 2. Auto-approve at the harness layer

The skill keeps emitting gates; the harness auto-answers them:

- **Claude Agent SDK** (`query()`): `permissionMode: 'bypassPermissions'`, a `canUseTool` callback that returns `{ behavior: 'allow' }`, and an `onElicitation` handler that returns the pre-supplied answers for any `AskUserQuestion`.
- **`claude -p`**: run non-interactively with a permission mode that doesn't block, and put all answers in the prompt.

Tell the skill explicitly: *"Proceed autonomously; do not wait for operator input — all approvals are pre-granted."*

## 3. Secrets via env only — never argv or the prompt

| Secret | Env var | Used by |
|---|---|---|
| mStudio API token | `MITTWALD_API_TOKEN` | `mw` CLI + HTTP API (also works as `Authorization: Bearer`) |
| Target SSH key / user | `MITTWALD_SSH_IDENTITY_FILE` / `MITTWALD_SSH_USER` | the SSH-tunnelling `mw` commands (`app exec`, `database mysql import`/`dump`) |
| Target DB password | `MYSQL_PWD` | `mysql` / `mw database mysql import` (password path) |
| Source SSH password | `SSHPASS` (with `sshpass -e`) | reaching a password-only source (Pitfall #28) |

Argv shows up in `ps` and shell history; never pass secrets there, and never echo them into the feed.

## 4. Make SSH non-interactive on both ends

- **Source**: password → `sshpass -e ssh -o StrictHostKeyChecking=accept-new`; key → `ssh -i <key> -o StrictHostKeyChecking=accept-new`; or a ready `~/.ssh/config` host. See [`ssh-modes.md`](ssh-modes.md) § "Source-side SSH access" and Pitfall #28.
- **Target**: point the `mw` SSH commands at the right key via `MITTWALD_SSH_IDENTITY_FILE` rather than editing `~/.ssh/config`.

## What does NOT change when headless

Everything else in the playbooks still applies — and matters *more* without a human watching:

- **Idempotent re-checks** on every step (a project/DB may already exist).
- **Verify by row counts and file counts**, not bytes (Pitfall #13).
- **Smoke-test on the default `<shortId>.project.space`** before any cutover (Pitfall #17).
- **Don't delete the source** (Pitfall #15) — headless runs must not decommission.
- Surface errors verbatim into the run's output; don't silently retry auth failures.

> Auto-approval removes the last human safety check. It is only safe when the operator has genuinely pre-authorized this exact source → target move. If a decision wasn't pre-supplied, the correct headless behavior is to **fail loudly**, not to guess.
