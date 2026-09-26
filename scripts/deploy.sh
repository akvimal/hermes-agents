#!/usr/bin/env bash
# Deploy on the VPS: pull, rebuild pharmacy-mcp, restart Hermes gateways.
#
#   scripts/deploy.sh                 # all profiles in profiles/ (except ones without a gateway)
#   PROFILES="me pharma-ops" scripts/deploy.sh
#   MCP_SERVICE=pharmacy-mcp scripts/deploy.sh   # also restart this systemd unit
#
# Assumes the repo is linked into the Hermes profiles (see scripts/link.ps1 for
# Windows; on the VPS link SOUL.md / config.yaml / skills the same way with ln -s).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

echo "==> git pull"
git pull --ff-only

echo "==> pharmacy-mcp: install + build + test"
(
  cd mcp/pharmacy-mcp
  npm ci
  npm test
  npm run build
)

if [[ -n "${MCP_SERVICE:-}" ]]; then
  echo "==> restarting $MCP_SERVICE"
  sudo systemctl restart "$MCP_SERVICE"
fi

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
