# hermes-agents

Source files for [Hermes Agent](https://github.com/NousResearch/hermes-agent) profiles, shared skills, cron jobs and the MCP servers they use. The repo holds what you author and version; Hermes keeps its own runtime state (credentials, sessions, memories, logs) outside git.

## Layout

```
hermes-agents/
├── profiles/               one folder per Hermes profile
│   ├── me/                 SOUL.md, config.yaml, skills/productivity/{email-brief,email-actions}
│   ├── pharma-ops/
│   └── pharma-growth/
├── shared-skills/          skills reused across profiles
├── mcp/
│   └── pharmacy-mcp/       NestJS MCP server (HTTP + stdio), with its own tests
├── cron/jobs.md            each job's schedule, prompt and skill
├── scripts/
│   ├── link.ps1            links the repo into the Hermes profile folders (Windows, native install)
│   ├── link.sh             same, for Linux / Docker
│   └── deploy.sh           git pull, link new files, rebuild MCP, reload gateways (Docker)
├── .env.example            environment variables, without values
└── .gitignore
```

## How the repo connects to Hermes

Nothing is copied. The Hermes profile is made to point at files in this repo, so an edit on either side is the same file — via symlinks (`scripts/link.ps1` natively, `scripts/link.sh` in Docker) or, in Docker's case, a bind mount plus those same symlinks created inside the container.

| Repo path | Linked to | Type |
| --- | --- | --- |
| `profiles/<p>/SOUL.md`, `config.yaml` | `<HERMES_HOME>/profiles/<p>/` | file symlink |
| `profiles/<p>/skills/[<category>/]<skill>/` | same path under `<HERMES_HOME>/profiles/<p>/skills/` | directory junction (native) / symlink (Docker) |
| `shared-skills/[<category>/]<skill>/` | same path in every profile's `skills/` | directory junction (native) / symlink (Docker) |

Native default: `<HERMES_HOME>` is `%LOCALAPPDATA%\hermes`. Docker: `<HERMES_HOME>` is whatever host directory
is bind-mounted to `/opt/data`. A profile's own skill wins over a shared skill of the same name. Everything
else in a Hermes profile (`.env`, `auth.json`, `sessions/`, `state.db`, `memories/`, `logs/`) stays local and
is git-ignored.

## Setup

Two ways to run Hermes against this repo, locally or on the VPS. **Docker is recommended** — it's what
runs in production, it's simpler on Windows than the native install (no Developer Mode, no symlink
permission workarounds), and the exact same steps work identically on the VPS.

### Docker (recommended)

Full steps, including every gotcha actually hit setting this up, are in
[docs/VPS_SETUP.md](docs/VPS_SETUP.md) — it reads the same for a laptop as for a VPS, with two
Windows-only simplifications:

- **Skip the `chown -R 10000:10000` step.** Docker Desktop's file-sharing layer doesn't enforce Unix
  ownership on Windows bind mounts, so the container's user can already read and write the repo — verified
  directly (a throwaway container, non-root, wrote into a bind-mounted file with no ownership fix needed).
- **The repo can live anywhere** (e.g. `D:\workspace\hermes-agents`) — Windows has no equivalent of Linux's
  `/root` blocking traversal, which is the only reason the VPS docs are strict about the mount path.

Everything else — creating profiles, linking the repo, starting the container, Telegram/Google Workspace
setup — is identical. Run the same `docker run` / `docker exec` commands from a Windows terminal.

### Native (no Docker)

Prerequisites: Hermes installed, Windows Developer Mode on (for file symlinks), Node 20+ for the MCP server.

```powershell
# 1. Create the Hermes profile once, if it doesn't exist
hermes profile create pharma-ops

# 2. Link the repo into Hermes (preview first)
.\scripts\link.ps1 -DryRun
.\scripts\link.ps1
```

`link.ps1` is safe to re-run. It skips empty scaffold files, and reports a conflict instead of overwriting a real file already in the profile.

To bring an existing profile's files into the repo, run with `-Adopt`:

- Repo file empty: the Hermes copy is moved into the repo, then linked.
- Repo file has content: the Hermes copy is backed up as `<name>.bak-<timestamp>`, then linked.

Stop the profile's gateway first (`hermes -p <profile> gateway stop`), because Hermes may rewrite `config.yaml` while it runs.

This is what `me` and `pharma-ops` originally ran on before moving to the VPS — kept here for reference and
because it's still a valid option if you'd rather not use Docker locally.

## Adding things

- **New profile:** create it in Hermes, add `profiles/<name>/` with `SOUL.md` and `config.yaml`, run `link.ps1`.
- **New skill:** add `profiles/<p>/skills/<category>/<skill>/SKILL.md` (or under `shared-skills/` for all profiles), run `link.ps1`. Any folder holding a `SKILL.md` counts as a skill; keep the same category folder Hermes uses (e.g. `productivity`).
- **New cron job:** document it in `cron/jobs.md`, then create it with `hermes -p <profile> cron create`. Hermes stores jobs in its own state, so the file is the record you recreate them from.

## Testing a change

New Hermes processes read the linked files fresh:

```powershell
hermes -p me config check
hermes -p me chat -q "Who are you and what are your rules?" -Q
```

A running gateway only picks up changes after a restart: `hermes -p me gateway restart`.

## MCP servers

`mcp/pharmacy-mcp` is a NestJS [MCP](https://modelcontextprotocol.io) server giving agents read-only access to the back office database (EOD, expiry, low stock, GST) over Streamable HTTP and stdio, through a dedicated `agent` schema in `mcp/pharmacy-mcp/sql/`. See [its README](mcp/pharmacy-mcp/README.md) for tools, configuration and tests.

```bash
cd mcp/pharmacy-mcp
npm install
npm test && npm run test:e2e
npm run start:dev        # http://127.0.0.1:3100/mcp
```

## Deploying to the VPS

Same Docker steps as the local setup above, plus the Linux-specific gotchas (file paths, permissions, the
multiplexed gateway model, Telegram, Google Workspace) — see [docs/VPS_SETUP.md](docs/VPS_SETUP.md). After
first-time setup:

```bash
scripts/deploy.sh                          # pull, link new files, rebuild pharmacy-mcp if it changed, reload gateways
PROFILES="me pharma-ops" scripts/deploy.sh # only these profiles
MCP_MODE=none scripts/deploy.sh            # skip the pharmacy-mcp rebuild check
```

`scripts/link.sh` is the Linux equivalent of `link.ps1`. `deploy.sh` assumes the persistent `hermes` container is already running (see docs/VPS_SETUP.md) — it reloads it, it never creates or recreates it.

## Secrets

Never commit credentials. `.env`, `auth.json`, `*token*.json`, `client_secret*.json`, sessions, state, logs and memories are git-ignored. Copy `.env.example` to `.env` and fill it in locally. This repo is public.

## Notes

- `link.ps1` uses `cmd /c mklink` for file symlinks because Windows PowerShell 5.1's `New-Item` needs admin even with Developer Mode on.
- If Hermes replaces a linked `config.yaml` with a plain file, the two copies drift apart. Re-running `link.ps1` reports it as a conflict rather than overwriting.
