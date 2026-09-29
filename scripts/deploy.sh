#!/usr/bin/env bash
# Deploy an update on the VPS: pull, link new files, rebuild pharmacy-mcp if it
# changed, reload each profile's gateway.
#
# Assumes the Docker deployment from docs/VPS_SETUP.md: a persistent container
# named `hermes` (image nousresearch/hermes-agent) with this repo bind-mounted
# read-write at the SAME absolute path inside and outside the container.
#
#   scripts/deploy.sh                          # all profiles under profiles/
#   PROFILES="me pharma-ops" scripts/deploy.sh # only these profiles
#   MCP_MODE=none scripts/deploy.sh            # skip the pharmacy-mcp rebuild check
#
# This script only reloads an already-running `hermes` container. It never
# recreates it - if you need to change its mounts, env vars, or UID mapping,
# that's a manual `docker stop/rm` + `docker run` (see docs/VPS_SETUP.md).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

if ! docker inspect hermes >/dev/null 2>&1; then
  echo "No container named 'hermes' found. Run the setup in docs/VPS_SETUP.md first." >&2
  exit 1
fi

before="$(git rev-parse HEAD)"
echo "==> git pull"
git pull --ff-only
after="$(git rev-parse HEAD)"

echo "==> re-chown repo files git pull just touched"
# git pull runs as root, which resets ownership on every file it writes/updates back to root:root -
# undoing the one-time `chown -R 10000:10000 /opt/hermes-agents` from setup for exactly the files
# that just changed. Without this, `hermes -p <profile> model`/`setup`/etc. fail with
# PermissionError writing config.yaml the next time you deploy an update. Re-chown the whole tree
# every run - cheap, and catches new files too, not just changed ones.
chown -R 10000:10000 "$REPO" 2>/dev/null || echo "    (chown failed/skipped - not root, or not on Linux; fix manually if a later step hits PermissionError)"

echo "==> link new profile/skill files into Hermes"
"$REPO/scripts/link.sh" --adopt

if [[ "${MCP_MODE:-}" != "none" ]] && [[ -d mcp/pharmacy-mcp ]]; then
  if git diff --name-only "$before" "$after" -- mcp/pharmacy-mcp | grep -q .; then
    echo "==> pharmacy-mcp changed - rebuilding"
    (cd mcp/pharmacy-mcp && docker compose up -d --build)
  else
    echo "==> pharmacy-mcp unchanged - skipping rebuild"
  fi
fi

if [[ -z "${PROFILES:-}" ]]; then
  PROFILES="$(find profiles -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | tr '\n' ' ')"
fi

echo "==> reloading profiles: $PROFILES"
for p in $PROFILES; do
  if docker exec hermes hermes -p "$p" config check >/dev/null 2>&1; then
    docker exec hermes hermes -p "$p" gateway restart \
      || echo "    $p: restart reported an issue - check 'docker exec hermes hermes -p $p gateway status'"
  else
    echo "    $p: no Hermes profile yet (run: docker exec hermes hermes profile create $p) - skipping"
  fi
done

echo "==> done"
docker exec hermes hermes gateway status
echo
echo "Reminder: config/SOUL.md changes apply on the next new session automatically."
echo "For a change to take effect mid-conversation, send /new in the chat, or wait for the restart above."
