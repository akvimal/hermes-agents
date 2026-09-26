# VPS setup

Order: install Hermes first, then bring in this repo for profiles, then the MCP server and cron jobs.
Assumes a Debian/Ubuntu VPS with Docker, and the back office Postgres already running in a container.

## 1. Run Hermes as its own user

```bash
# as root
adduser --disabled-password --gecos "" hermes
usermod -aG docker hermes          # lets it run `docker compose` for pharmacy-mcp
loginctl enable-linger hermes      # user services keep running after logout and start at boot
apt update && apt install -y git curl
timedatectl set-timezone Asia/Kolkata   # cron expressions and "today" follow the server clock
```

## 2. Install Hermes

```bash
sudo -iu hermes
curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o install-hermes.sh
less install-hermes.sh             # read it before running it
bash install-hermes.sh
source ~/.bashrc
hermes --version
hermes doctor
```

Hermes home on Linux is `~/.hermes`. Profiles live in `~/.hermes/profiles/<name>`.

## 3. Base configuration (provider and keys)

```bash
hermes setup                       # provider, model, tools
```

API keys and bot tokens go into `~/.hermes/.env` and each profile's own `.env`. They are never committed.

## 4. Get this repo

```bash
git clone https://github.com/akvimal/hermes-agents.git ~/hermes-agents
```

## 5. Create the profiles and link the repo

```bash
hermes profile create me --description "Personal email and calendar assistant"
hermes profile create pharma-ops --description "Pharmacy operations: EOD, purchase, GST"
hermes profile create pharma-growth --description "Customer messaging: refills, welcome, awareness"

~/hermes-agents/scripts/link.sh --adopt --dry-run    # preview
~/hermes-agents/scripts/link.sh --adopt              # first time only
```

`--adopt` handles the first run:
- `me`: the repo has content, so any file Hermes generated is backed up as `<name>.bak-<time>` and the repo copy is linked.
- `pharma-ops` and `pharma-growth`: the repo has no files yet, so the files Hermes generated move into the repo as the starting copies. Edit them there, then commit.

After that, `scripts/link.sh` (no flags) is safe to re-run and only adds what is new. `deploy.sh` runs it for you.

## 6. Per-profile secrets and messaging

```bash
hermes -p me config env-path            # shows the .env to edit (API keys, bot token)
hermes -p me gateway setup              # Telegram etc.
```

- **One Telegram bot token, one running gateway.** Stop the gateway on your PC before starting the same
  profile here (`hermes -p me gateway stop`), or give the VPS its own bot.
- **Google access for `me`** (Gmail/Calendar): re-run the google-workspace skill's auth on the VPS, or copy
  `google_client_secret.json` and `google_token.json` from your PC's `me` profile folder with `scp`
  (`chmod 600` them). They stay outside git.

## 7. Run the gateways as services

```bash
hermes -p me gateway install --start-now
hermes -p pharma-ops gateway install --start-now
hermes gateway list
```

`--system --run-as-user hermes` installs a boot-level service instead (needs root); with `enable-linger`
the default user-level service already survives reboots.

## 8. The pharmacy MCP server (Docker)

Find the Postgres container and its network:

```bash
docker ps --format '{{.Names}}\t{{.Image}}'
docker inspect <postgres-container> --format '{{json .NetworkSettings.Networks}}'
```

Create the read-only database role (see `mcp/pharmacy-mcp/README.md`), applying the SQL through the container:

```bash
cd ~/hermes-agents/mcp/pharmacy-mcp/sql
docker exec -i <postgres-container> psql -U <owner> -d <db> -v ON_ERROR_STOP=1 < 001_agent_views.sql
docker exec -i <postgres-container> psql -U <superuser> -d <db> -v ON_ERROR_STOP=1 < 002_agent_role.sql
docker exec -i <postgres-container> psql -U <superuser> -d <db> -c "ALTER ROLE agent_ro PASSWORD '<secret>'"
docker exec -i <postgres-container> psql -U <owner> -d <db> -v ON_ERROR_STOP=1 < tests/check_agent_views.sql
```

Configure and start it (the file is git-ignored; keep it private):

```bash
cd ~/hermes-agents/mcp/pharmacy-mcp
cat > .env <<EOF
DATABASE_URL=postgresql://agent_ro:<secret>@<postgres-container>:5432/<db>
DB_NETWORK=<network from docker inspect>
MCP_AUTH_TOKEN=$(openssl rand -hex 24)
EOF
chmod 600 .env
docker compose up -d --build
curl -s http://127.0.0.1:3100/health
```

The MCP listens on the host's loopback only, and Postgres needs no published port.

Register it with the profile that should use it, then check:

```bash
hermes -p pharma-ops mcp add pharmacy --url http://127.0.0.1:3100/mcp --auth header
hermes -p pharma-ops mcp list
```

Hermes asks for the bearer token (paste the `MCP_AUTH_TOKEN` value from the step above). It stores the token in
the profile's `.env` and writes only an `Authorization: Bearer ${...}` placeholder into `config.yaml`. That file
is linked to the repo, so the change is safe to commit and the secret never enters git.

## 9. Cron jobs

Hermes stores jobs in its own state, so recreate them from `cron/jobs.md`:

```bash
hermes -p me cron create "0 20 * * *" "<prompt from cron/jobs.md>" \
  --name daily-email-brief --skill email-brief --skill google-workspace --deliver telegram
hermes -p me cron list
```

Avoid duplicates: if the same job still runs on your PC, pause or remove it there.

## 10. Updating later

```bash
~/hermes-agents/scripts/deploy.sh      # git pull, link new files, rebuild pharmacy-mcp, restart gateways
hermes update                          # Hermes itself
```
