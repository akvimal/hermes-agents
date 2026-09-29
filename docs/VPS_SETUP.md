# VPS setup (Docker)

This is the deployment actually running in production, built and debugged step by step on
2026-09-27/28. It uses the official `nousresearch/hermes-agent` Docker image — **one container
runs the messaging gateway for every profile** (a "multiplexer"), not one process per profile.

## 0. Prerequisites

- Docker installed on the VPS.
- This repo cloned at **`/opt/hermes-agents`** — not `/root/hermes-agents`, not `/root/apps/hermes-agents`.
  Anything under `/root` is unreadable to the container's non-root process (`/root` is `0700`), no matter
  how deep the file actually is. `/opt` is world-traversable, which is why it works.

```bash
git clone https://github.com/akvimal/hermes-agents.git /opt/hermes-agents
```

## 1. First-time setup wizard

```bash
mkdir -p ~/.hermes
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent setup
```
Pick **Quick Setup (Nous Portal)** unless you have a specific reason not to — free, OAuth, no key to
type into a VPS console (some providers' browser consoles corrupt pasted special characters).

If you're connecting over a provider's browser console rather than SSH, don't paste secrets into it —
type them, and double-check every `:`, `@`, `=`.

## 2. Create profiles and link the repo — before starting the persistent container

```bash
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent profile create me --description "Personal assistant"
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent profile create pharma-ops --description "Pharmacy operations"
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent profile create pharma-growth --description "Customer messaging"

HERMES_HOME=~/.hermes /opt/hermes-agents/scripts/link.sh --adopt --dry-run   # preview
HERMES_HOME=~/.hermes /opt/hermes-agents/scripts/link.sh --adopt
```
`--adopt`: if the repo's `SOUL.md`/`config.yaml` is empty, the freshly-generated Hermes copy moves into
the repo as the starting point; if the repo already has real content, the Hermes copy is backed up as
`.bak-<timestamp>` and replaced with a link to the repo's version.

## 3. Start the persistent container

```bash
chown -R 10000:10000 /opt/hermes-agents

docker network create hermes-net   # once - shared with pharmacy-mcp and any future MCP server

docker run -d --name hermes --restart unless-stopped \
  --network hermes-net \
  -v ~/.hermes:/opt/data \
  -v /opt/hermes-agents:/opt/hermes-agents \
  -p 8642:8642 \
  nousresearch/hermes-agent gateway run
```

`--network hermes-net` replaces Docker's default bridge network, not `-p 8642:8642` — port publishing still
works the same. This matters for step 7 (pharmacy-mcp): a container's `127.0.0.1` is its own loopback, not
the host's, so reaching another container by `127.0.0.1:<port>` never works regardless of what that port
publishes to on the host. Every MCP server this profile talks to needs to be on `hermes-net` too, addressed
by its container name — see step 7.

Two things that **must** both be true, or Hermes can't read/write the linked files:

- **The mount must not be `:ro`.** Config edits (`hermes setup`, `hermes model`, `gateway setup`, ...) write
  through the `config.yaml`/`SOUL.md` symlinks back into the repo — a read-only mount turns that into
  `OSError: Read-only file system`.
- **The `chown`.** The container's internal `hermes` user is UID 10000. The image's own startup hook
  auto-fixes ownership on `/opt/data`, but has no idea about this extra mount, so files here (cloned/created
  as root) stay root-owned unless you chown them — a mismatch shows up as `PermissionError`, not
  `Read-only file system`, so the two errors tell you which piece is still wrong.
  **This isn't one-and-done** — every `git pull` runs as root and resets ownership on whatever files it
  touches, so the exact same `PermissionError` comes back the next time you deploy an update and then run
  `hermes -p <profile> model`/`setup`/anything else that writes `config.yaml`. `scripts/deploy.sh` re-chowns
  the whole repo after every pull for this reason — if you ever update by hand instead, re-run the `chown`
  below yourself afterward.

```bash
docker ps --filter name=hermes                                    # confirm it's up
docker exec hermes ls -la /opt/data/profiles/me/config.yaml       # should show -> /opt/hermes-agents/...
docker exec hermes hermes -p me config check
docker exec hermes hermes -p me -z "reply with exactly: OK"
```

## 4. Messaging (Telegram)

```bash
docker exec -it hermes hermes -p me gateway setup
```

**Gotcha #1 — the gateway model.** There is no separate `me` process to "start" or "restart" the way a
native/systemd install works. `docker exec hermes hermes -p me gateway status` will say *"Gateway is
running via the default-profile multiplexer"* — that's correct, not broken. All profiles' Telegram polling
runs inside the one shared `hermes` container process; you just add a profile's bot token and it connects.
`docker exec hermes hermes gateway status` (no `-p`, i.e. the `default` profile) shows the actual shared
process and every profile it's serving.

**Gotcha #2 — `TELEGRAM_ALLOWED_USERS` is easy to leave blank or wrong**, and the failure is silent: the
bot connects and polls fine, but every message from you gets logged as `Unauthorized user: <id>` and
dropped, with nothing sent back. Confirm it explicitly:
```bash
docker exec hermes cat /opt/data/profiles/me/.env | grep TELEGRAM_ALLOWED_USERS
```
Should show your real numeric Telegram user ID. If wrong, redo it (`docker exec -it hermes hermes -p me
setup gateway --reset` clears the section first) and `docker restart hermes` afterward — safer than relying
on the ~30s auto-rescan for env var changes to take effect.

**Migrating an existing bot from a laptop/desktop install:** a Telegram bot token can only be polled by one
running gateway at a time. Stop and fully **uninstall** (not just stop — it's a login item and will restart
on next login) the old one before configuring the same token here:
```powershell
hermes -p me gateway stop
hermes -p me gateway uninstall
```

**Verify end to end:**
```bash
docker logs -f hermes
```
Send the bot a real message. It should be logged and answered within a couple seconds.

## 5. Google Workspace (Gmail/Calendar), for any profile that needs it

Two independent gotchas here, both silent otherwise:

**a. Copy credentials to the right (non-profile-scoped) path.** Despite living under `profiles/<name>/` on
a native install, the Docker image's `google-workspace` skill reads from the top level of `$HERMES_HOME`:
```powershell
scp "$env:LOCALAPPDATA\hermes\profiles\me\google_client_secret.json" root@<vps>:/root/.hermes/google_client_secret.json
scp "$env:LOCALAPPDATA\hermes\profiles\me\google_token.json" root@<vps>:/root/.hermes/google_token.json
```
```bash
chown 10000:10000 /root/.hermes/google_client_secret.json /root/.hermes/google_token.json
chmod 600 /root/.hermes/google_client_secret.json /root/.hermes/google_token.json
```
The `chown` matters as much as the `chmod` — `scp` leaves these root-owned, and the running agent (UID
10000) silently reports "Gmail isn't authenticated" rather than a permission error if it can't read them.

**b. The skill's own Python dependencies aren't baked into the image.** `google-api-python-client`,
`google-auth-oauthlib`, and `google-auth-httplib2` are missing, and the container deliberately seals its
Python environment so the agent (non-root) can't install them itself. Install as root, which *can* write
there:
```bash
docker exec hermes sh -c 'uv pip install --python "$(which python3)" google-api-python-client google-auth-oauthlib google-auth-httplib2'
docker exec hermes python3 -c "import googleapiclient, google_auth_oauthlib; print('ok')"
```
This lands in the container's writable layer, not a mounted volume — it survives `docker restart` and VPS
reboots, but is **lost if the container is ever `docker rm`'d and recreated**. Re-run it after any such
recreate.

**Check auth status directly** (bypasses the running agent, useful for diagnosing which of (a)/(b) is
still wrong):
```bash
docker exec hermes python /opt/data/profiles/me/skills/productivity/google-workspace/scripts/setup.py --check
```

## 6. Auxiliary-task spend

Background tasks (session title generation, the "smart approvals" auto-approve guardian) default to
whatever paid model is configured and can fail outright if that provider has no credit, or burn real
spend on a paid model you didn't intend to use for background work. Restrict them to free models:
```bash
docker exec hermes hermes -p me config set auxiliary.free_only true
```

## 7. The pharmacy MCP server

Runs as its own separate container (`mcp/pharmacy-mcp`), independent of the `hermes` container. See
`mcp/pharmacy-mcp/README.md` for the database role setup. Its `docker-compose.yml` auto-joins `hermes-net`
(created in step 3) and gives the container a stable name, `pharmacy-mcp`:
```bash
cd mcp/pharmacy-mcp
docker compose up -d --build
```

**Do not use `http://127.0.0.1:3100/mcp`** — verified this fails (`Connection failed`) even though the port
is published on the host, because `hermes` and `pharmacy-mcp` are separate containers: `127.0.0.1` inside
`hermes` is its own loopback, not the host's. Address it by its container name over the shared network
instead — this is what `profiles/pharma-ops/config.yaml` already has committed:
```yaml
mcp_servers:
  pharmacy:
    url: http://pharmacy-mcp:3100/mcp
```
The interactive `hermes mcp add` wizard doesn't know about container-name addressing and will happily save
a `127.0.0.1` URL that silently fails later — edit `config.yaml` directly instead (already done for
`pharma-ops`), then add the token to the profile's `.env`:
```bash
docker exec hermes cat /opt/hermes-agents/mcp/pharmacy-mcp/.env | grep MCP_AUTH_TOKEN   # get the token
echo "MCP_PHARMACY_API_KEY=<paste the token>" >> ~/.hermes/profiles/pharma-ops/.env
docker restart hermes   # or wait for the ~30s auto-rescan
docker exec hermes hermes -p pharma-ops mcp test pharmacy
```

## 8. Cron jobs

Cron state lives in each install's own data, so it does **not** migrate with the repo. Recreate every job
listed in `cron/jobs.md`:
```bash
docker exec hermes hermes -p me cron create "0 20 * * *" "<prompt from cron/jobs.md>" --name daily-email-brief --skill email-brief --skill google-workspace --deliver telegram
docker exec hermes hermes -p me cron list
docker exec hermes hermes -p me cron run <job_id>   # trigger once to test delivery without waiting
```
If the same job is still scheduled on a laptop/desktop install you're migrating away from, remove it there
too, or you'll get the message twice.

## 9. Routine updates after all this is working

```bash
/opt/hermes-agents/scripts/deploy.sh
```
Pulls, links any new profile/skill files, rebuilds `pharmacy-mcp` only if its source changed, and reloads
each profile's gateway. It never recreates the `hermes` container — if you need to change its mounts, env
vars, or UID mapping, that's a manual `docker stop`/`rm` + `docker run` following section 3 above.
