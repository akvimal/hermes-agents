# hermes-agents

Source files for [Hermes Agent](https://github.com/NousResearch/hermes-agent) profiles, shared skills, cron jobs and the MCP servers they use. The repo holds what you author and version; Hermes keeps its own runtime state (credentials, sessions, memories, logs) outside git.

## Layout

```
hermes-agents/
├── profiles/               one folder per Hermes profile
│   ├── me/                 SOUL.md, config.yaml, skills/{email-brief,email-actions}
│   ├── pharma-ops/
│   └── pharma-growth/
├── shared-skills/          skills reused across profiles
├── mcp/
│   └── pharmacy-mcp/       NestJS MCP server (HTTP + stdio), with its own tests
├── cron/jobs.md            each job's schedule, prompt and skill
├── scripts/
│   ├── link.ps1            links the repo into the Hermes profile folders (Windows)
│   └── deploy.sh           git pull, rebuild MCP, restart gateways (VPS)
├── .env.example            environment variables, without values
└── .gitignore
```

## How the repo connects to Hermes

Nothing is copied. `scripts/link.ps1` makes the Hermes profile point at files in this repo, so an edit on either side is the same file.

| Repo path | Linked to | Type |
| --- | --- | --- |
| `profiles/<p>/SOUL.md`, `config.yaml` | `<HERMES_HOME>/profiles/<p>/` | file symlink |
| `profiles/<p>/skills/<skill>/` | `<HERMES_HOME>/profiles/<p>/skills/<skill>/` | directory junction |
| `shared-skills/<skill>/` | every profile's `skills/<skill>/` | directory junction |

`<HERMES_HOME>` defaults to `%LOCALAPPDATA%\hermes`. A profile's own skill wins over a shared skill of the same name. Everything else in a Hermes profile (`.env`, `auth.json`, `sessions/`, `state.db`, `memories/`, `logs/`) stays local and is git-ignored.

## Setup (Windows)

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

## Adding things

- **New profile:** create it in Hermes, add `profiles/<name>/` with `SOUL.md` and `config.yaml`, run `link.ps1`.
- **New skill:** add `profiles/<p>/skills/<skill>/SKILL.md` (or `shared-skills/<skill>/` for all profiles), run `link.ps1`.
- **New cron job:** document it in `cron/jobs.md`, then create it with `hermes -p <profile> cron create`. Hermes stores jobs in its own state, so the file is the record you recreate them from.

## Testing a change

New Hermes processes read the linked files fresh:

```powershell
hermes -p me config check
hermes -p me chat -q "Who are you and what are your rules?" -Q
```

A running gateway only picks up changes after a restart: `hermes -p me gateway restart`.

## MCP servers

`mcp/pharmacy-mcp` is a NestJS [MCP](https://modelcontextprotocol.io) server exposing pharmacy inventory tools over Streamable HTTP and stdio. See [its README](mcp/pharmacy-mcp/README.md) for tools, configuration and tests.

```bash
cd mcp/pharmacy-mcp
npm install
npm test && npm run test:e2e
npm run start:dev        # http://127.0.0.1:3100/mcp
```

## Deploying to the VPS

```bash
git clone https://github.com/akvimal/hermes-agents.git
scripts/deploy.sh                          # pull, npm ci, test, build, restart gateways
PROFILES="me pharma-ops" scripts/deploy.sh # only these profiles
MCP_SERVICE=pharmacy-mcp scripts/deploy.sh # also restart a systemd unit
```

On Linux, link the repo files into the Hermes profile folders with `ln -s` (the equivalent of `link.ps1`, not scripted yet). Run `hermes` under the same user that owns the profiles.

## Secrets

Never commit credentials. `.env`, `auth.json`, `*token*.json`, `client_secret*.json`, sessions, state, logs and memories are git-ignored. Copy `.env.example` to `.env` and fill it in locally. This repo is public.

## Notes

- `link.ps1` uses `cmd /c mklink` for file symlinks because Windows PowerShell 5.1's `New-Item` needs admin even with Developer Mode on.
- If Hermes replaces a linked `config.yaml` with a plain file, the two copies drift apart. Re-running `link.ps1` reports it as a conflict rather than overwriting.
