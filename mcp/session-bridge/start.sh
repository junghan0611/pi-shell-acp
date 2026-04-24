#!/usr/bin/env bash
# session-bridge MCP server launcher
# Derives SESSION_NAME from the working directory if not set.
# CWD is typically the project root when Claude Code launches MCP servers.

if [ -z "$SESSION_NAME" ]; then
  # Use the project directory name as session name
  SESSION_NAME=$(basename "$PWD")
fi

export SESSION_NAME
exec node "$(dirname "$0")/dist/index.js"
