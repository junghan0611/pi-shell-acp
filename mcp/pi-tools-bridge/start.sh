#!/usr/bin/env bash
# pi-tools-bridge MCP server launcher.
#
# Runs src/index.ts directly via Node's --experimental-strip-types; no separate
# build step. Node >= 22.6 (engines.node in ../../package.json).
#
# Env file loading is strictly opt-in — the launcher never reads any dotfile
# unless PI_TOOLS_BRIDGE_ENV_FILE points at one. Rationale: pi-shell-acp is a
# public package; baking in personal conventions (~/.env.local, etc.) would
# bleed the original author's dotfile habits into every consumer's shell.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -n "${PI_TOOLS_BRIDGE_ENV_FILE:-}" ] && [ -f "$PI_TOOLS_BRIDGE_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$PI_TOOLS_BRIDGE_ENV_FILE"
  set +a
fi

# All chatter goes to stderr so it never confuses an MCP client reading
# JSON-RPC frames from stdout.
exec node --experimental-strip-types --disable-warning=ExperimentalWarning \
  "$HERE/src/index.ts"
