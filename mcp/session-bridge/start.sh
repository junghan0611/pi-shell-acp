#!/usr/bin/env bash
# session-bridge MCP server launcher.
#
# Runs src/index.ts directly via Node's --experimental-strip-types; no build
# step. Node >= 22.6 (engines.node in ../../package.json).
#
# SESSION_NAME defaults to the CWD basename (Claude Code launches MCP servers
# from the project root), but the caller can override by exporting it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${SESSION_NAME:-}" ]; then
  SESSION_NAME=$(basename "$PWD")
fi
export SESSION_NAME

exec node --experimental-strip-types --disable-warning=ExperimentalWarning \
  "$HERE/src/index.ts"
