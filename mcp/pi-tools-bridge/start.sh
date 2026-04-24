#!/usr/bin/env bash
# pi-tools-bridge launcher.
#
# Loads an env file so downstream CLIs (andenken) find GEMINI_API_KEY /
# ANDENKEN_PROVIDER / etc.  Override the env file with PI_TOOLS_BRIDGE_ENV_FILE.
#
# Defensive stale-dist guard:
# pi-shell-acp spawns this launcher per ACP session and treats whatever it gets
# as the MCP server. If src/** has been edited since the last build, the
# launcher would silently serve stale code (this was a real "MCP not visible"
# failure mode). We re-run `npm run build` when src is newer than dist.
# Skip the guard with PI_TOOLS_BRIDGE_SKIP_REBUILD=1 in CI / smoke paths that
# already build explicitly.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${PI_TOOLS_BRIDGE_ENV_FILE:-$HOME/.env.local}"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

DIST_ENTRY="$HERE/dist/mcp/pi-tools-bridge/src/index.js"
BRIDGE_SRC="$HERE/src/index.ts"
CORE_SRC="$HERE/../../pi-extensions/lib/delegate-core.ts"

if [ "${PI_TOOLS_BRIDGE_SKIP_REBUILD:-}" != "1" ]; then
  if [ ! -f "$DIST_ENTRY" ] \
     || [ "$BRIDGE_SRC" -nt "$DIST_ENTRY" ] \
     || [ -f "$CORE_SRC" -a "$CORE_SRC" -nt "$DIST_ENTRY" ]; then
    # All build chatter goes to stderr so it never confuses an MCP client
    # reading JSON-RPC frames from stdout.
    echo "[pi-tools-bridge] dist stale — rebuilding" >&2
    (cd "$HERE" && npm run build >&2)
  fi
fi

exec node "$DIST_ENTRY"
