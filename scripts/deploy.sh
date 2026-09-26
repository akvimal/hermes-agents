#!/usr/bin/env bash
# Deploy on the VPS: pull, link new profile files, rebuild pharmacy-mcp, restart Hermes gateways.
#
#   scripts/deploy.sh                          # pharmacy-mcp in Docker, restart every profile's gateway
#   PROFILES="me pharma-ops" scripts/deploy.sh # restart only these gateways
#   MCP_MODE=host scripts/deploy.sh            # build with the host's Node instead of Docker
#   MCP_MODE=none scripts/deploy.sh            # skip pharmacy-mcp
#   MCP_SERVICE=pharmacy-mcp scripts/deploy.sh # host mode: also restart this systemd --user unit
#
# Docker mode reads mcp/pharmacy-mcp/.env (DATABASE_URL, DB_NETWORK, MCP_AUTH_TOKEN); see its README.
# Host mode needs Node 24 (the version the lockfile was created with).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
MCP_MODE="${MCP_MODE:-docker}"

echo "==> git pull"
git pull --ff-only

echo "==> link profile files into Hermes"
scripts/link.sh   # links new skills/files; reports conflicts instead of overwriting

case "$MCP_MODE" in
  docker)
    echo "==> pharmacy-mcp: docker compose up --build"
    (cd mcp/pharmacy-mcp && docker compose up -d --build)
    ;;
  host)
    echo "==> pharmacy-mcp: install + test + build"
    (cd mcp/pharmacy-mcp && npm ci && npm test && npm run build)
    if [[ -n "${MCP_SERVICE:-}" ]]; then
      echo "==> restarting $MCP_SERVICE"
      systemctl --user restart "$MCP_SERVICE"
    fi
    ;;
  none) ;;
  *) echo "unknown MCP_MODE: $MCP_MODE (docker|host|none)" >&2; exit 2 ;;
esac

if [[ -z "${PROFILES:-}" ]]; then
  PROFILES="$(find profiles -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | tr '\n' ' ')"
fi

echo "==> restarting gateways: $PROFILES"
failed=()
for p in $PROFILES; do
  if hermes -p "$p" gateway restart; then
    echo "    $p: restarted"
  else
    echo "    $p: FAILED" >&2
    failed+=("$p")
  fi
done

if ((${#failed[@]})); then
  echo "Gateway restart failed for: ${failed[*]}" >&2
  exit 1
fi

echo "==> done"
hermes gateway list
