#!/usr/bin/env bash
# pi-tools-bridge smoke tests.
#
# Two layers:
#   1. Protocol parity — tools/list must return exactly the expected tool names.
#      No external deps. Always runnable.
#   2. End-to-end (opt-in via E2E=1) — exercises knowledge_search against a real
#      embedding provider, and send_to_session against a non-existent target to
#      assert the error path.
#
# Usage:
#   ./test.sh              # protocol-only
#   E2E=1 ./test.sh        # full suite (requires ~/.env.local + andenken index)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
EXPECTED_TOOLS=("session_search" "knowledge_search" "send_to_session" "list_sessions" "delegate" "delegate_resume")
PASS=0
FAIL=0

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }

ok()   { green "  ✓ $1"; PASS=$((PASS+1)); }
fail() { red   "  ✗ $1"; FAIL=$((FAIL+1)); }

DIST_ENTRY="$HERE/dist/mcp/pi-tools-bridge/src/index.js"
CORE_SRC="$HERE/../../pi-extensions/lib/delegate-core.ts"

# Build if stale.
if [ ! -f "$DIST_ENTRY" ] \
   || [ "$HERE/src/index.ts" -nt "$DIST_ENTRY" ] \
   || [ "$CORE_SRC" -nt "$DIST_ENTRY" ]; then
  echo "[build]"
  (cd "$HERE" && npm run build >/dev/null)
fi

rpc() {
  # stdin: newline-delimited JSON-RPC requests
  # stdout: server responses, trimmed to 5s
  timeout 10 "$HERE/start.sh"
}

# ----------------------------------------------------------------------------
# 1. Protocol — tools/list returns expected names
# ----------------------------------------------------------------------------

echo "[1] tools/list parity"

TOOLS_JSON=$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    sleep 0.5
  } | rpc 2>/dev/null | grep '"id":2' || true
)

if [ -z "$TOOLS_JSON" ]; then
  fail "no tools/list response"
else
  for tool in "${EXPECTED_TOOLS[@]}"; do
    if echo "$TOOLS_JSON" | grep -q "\"name\":\"$tool\""; then
      ok "exposes $tool"
    else
      fail "missing $tool"
    fi
  done
fi

# ----------------------------------------------------------------------------
# 2. Error paths — unknown tool + missing required arg
# ----------------------------------------------------------------------------

echo "[2] error surfaces"

UNKNOWN=$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"nonexistent_tool","arguments":{}}}'
    sleep 0.5
  } | rpc 2>/dev/null | grep '"id":9' || true
)
if echo "$UNKNOWN" | grep -qE '"(error|isError)"'; then
  ok "unknown tool rejected"
else
  fail "unknown tool did not surface error: $UNKNOWN"
fi

# ----------------------------------------------------------------------------
# 3. send_to_session negative path — no process, should isError:true
# ----------------------------------------------------------------------------

echo "[3] send_to_session negative path"

SEND=$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"send_to_session","arguments":{"target":"__definitely_does_not_exist__","message":"hi"}}}'
    sleep 0.5
  } | rpc 2>/dev/null | grep '"id":10' || true
)
if echo "$SEND" | grep -q '"isError":true'; then
  ok "missing socket returns isError"
else
  fail "missing socket did not surface isError: $SEND"
fi

# ----------------------------------------------------------------------------
# 3b. list_sessions — must succeed (not isError) even when no live sessions exist
# ----------------------------------------------------------------------------

echo "[3b] list_sessions empty environment"

LIST=$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"list_sessions","arguments":{}}}'
    sleep 1
  } | rpc 2>/dev/null | grep '"id":15' || true
)
if echo "$LIST" | grep -q '"isError":true'; then
  fail "list_sessions reported isError on empty env: ${LIST:0:200}"
elif echo "$LIST" | grep -qE 'controlDir'; then
  ok "list_sessions returns controlDir + sessions payload"
else
  fail "list_sessions produced no payload: ${LIST:0:200}"
fi

# ----------------------------------------------------------------------------
# 4. delegate negative path — bogus SSH host should surface isError
# ----------------------------------------------------------------------------

echo "[4] delegate bogus-ssh negative path"

DELEGATE_NEG=$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"delegate","arguments":{"task":"noop","host":"__pi_tools_bridge_bogus_host__"}}}'
    sleep 3
  } | timeout 15 "$HERE/start.sh" 2>/dev/null | grep '"id":20' || true
)
if echo "$DELEGATE_NEG" | grep -q '"isError":true'; then
  ok "bogus SSH host returns isError"
else
  fail "bogus SSH host did not surface isError: ${DELEGATE_NEG:0:200}"
fi

# ----------------------------------------------------------------------------
# 4b. delegate_resume negative path — unknown taskId must surface isError
# ----------------------------------------------------------------------------

echo "[4b] delegate_resume unknown taskId"

RESUME_NEG=$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"delegate_resume","arguments":{"taskId":"__definitely_does_not_exist__","prompt":"noop"}}}'
    sleep 1
  } | rpc 2>/dev/null | grep '"id":21' || true
)
if echo "$RESUME_NEG" | grep -q '"isError":true' && echo "$RESUME_NEG" | grep -q 'session_not_found'; then
  ok "unknown taskId returns isError + session_not_found"
else
  fail "unknown taskId did not surface session_not_found: ${RESUME_NEG:0:200}"
fi

# ----------------------------------------------------------------------------
# 4c-4e. Schema + registry gates — fetch tools/list once, then assert against it.
# ----------------------------------------------------------------------------

SCHEMA_JSON=$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":22,"method":"tools/list"}'
    sleep 0.5
  } | rpc 2>/dev/null | grep '"id":22' || true
)

# 4c. Identity Preservation Rule — delegate_resume schema must NOT expose `model`.
echo "[4c] delegate_resume schema lockdown (no model param)"
RESUME_SCHEMA=$(echo "$SCHEMA_JSON" | python3 -c "
import json, sys
try:
  o = json.loads(sys.stdin.read())
  t = next((x for x in o['result']['tools'] if x['name'] == 'delegate_resume'), None)
  if t is None: print('NOT_FOUND'); sys.exit(0)
  props = list(t['inputSchema'].get('properties', {}).keys())
  print(','.join(sorted(props)))
except Exception as e:
  print('PARSE_ERROR:', e)
")
if [ "$RESUME_SCHEMA" = "NOT_FOUND" ]; then
  fail "delegate_resume tool not in tools/list: ${SCHEMA_JSON:0:200}"
elif echo "$RESUME_SCHEMA" | grep -qw model; then
  fail "delegate_resume schema exposes 'model' (Identity Preservation Rule violation): $RESUME_SCHEMA"
elif ! echo "$RESUME_SCHEMA" | grep -qw taskId; then
  fail "delegate_resume schema unexpectedly missing 'taskId': $RESUME_SCHEMA"
else
  ok "delegate_resume schema has no 'model' (locked): $RESUME_SCHEMA"
fi

# 4d. delegate schema must expose the new `provider` field for registry-aware calls.
echo "[4d] delegate schema exposes provider field"
DELEGATE_SCHEMA=$(echo "$SCHEMA_JSON" | python3 -c "
import json, sys
try:
  o = json.loads(sys.stdin.read())
  t = next((x for x in o['result']['tools'] if x['name'] == 'delegate'), None)
  if t is None: print('NOT_FOUND'); sys.exit(0)
  print(','.join(sorted(t['inputSchema'].get('properties', {}).keys())))
except Exception as e:
  print('PARSE_ERROR:', e)
")
if [ "$DELEGATE_SCHEMA" = "NOT_FOUND" ]; then
  fail "delegate tool not in tools/list"
elif ! echo "$DELEGATE_SCHEMA" | grep -qw provider; then
  fail "delegate schema missing 'provider' field: $DELEGATE_SCHEMA"
elif ! echo "$DELEGATE_SCHEMA" | grep -qw model; then
  fail "delegate schema missing 'model' field: $DELEGATE_SCHEMA"
else
  ok "delegate schema exposes provider + model: $DELEGATE_SCHEMA"
fi

# 4f. Static guard against the PM-flagged blocker class: runDelegateAsync in
#     pi-extensions/delegate.ts must reference the local `routing` variable, not
#     the legacy `explicitExtensions` (which was renamed). Catches a regression
#     class that the bridge's tsconfig cannot see (pi-extensions is outside its
#     include path, so a stale name compiles silently and only fails at runtime).
echo "[4d2] static guard: runDelegateAsync uses 'routing' (no stale name)"
NATIVE_FILE="$HERE/../../pi-extensions/delegate.ts"
if [ ! -f "$NATIVE_FILE" ]; then
  fail "static guard: native delegate.ts not found at $NATIVE_FILE"
else
  STALE_REFS=$(awk '/^async function runDelegateAsync/,/^\}$/' "$NATIVE_FILE" \
    | grep -nE '\bexplicitExtensions\.' \
    | grep -v 'info\.explicitExtensions' \
    | grep -v 'resumeInfo\.explicitExtensions' \
    || true)
  if [ -z "$STALE_REFS" ]; then
    ok "runDelegateAsync clean (no stale 'explicitExtensions.X' references)"
  else
    fail "runDelegateAsync still references stale 'explicitExtensions': $STALE_REFS"
  fi
fi

# 4e. Registry runtime gate — unregistered (provider, model) must be rejected.
echo "[4e] delegate registry — unregistered (provider, model) rejected"
REGISTRY_NEG=$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"delegate","arguments":{"task":"noop","host":"__bogus__","provider":"__not_a_provider__","model":"__not_a_model__"}}}'
    sleep 1
  } | rpc 2>/dev/null | grep '"id":23' || true
)
if echo "$REGISTRY_NEG" | grep -q '"isError":true' \
   && echo "$REGISTRY_NEG" | grep -q 'not in the delegate target registry' \
   && echo "$REGISTRY_NEG" | grep -q 'Allowed:'; then
  ok "unregistered (provider, model) rejected with allowed-list hint"
else
  fail "unregistered tuple did not surface registry rejection: ${REGISTRY_NEG:0:300}"
fi

# ----------------------------------------------------------------------------
# 5. E2E (opt-in) — real knowledge_search call
# ----------------------------------------------------------------------------

if [ "${E2E:-0}" = "1" ]; then
  echo "[5] e2e knowledge_search"
  RESULT=$(
    {
      printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
      printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
      printf '%s\n' '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"knowledge_search","arguments":{"query":"MCP bridge","limit":2}}}'
      sleep 30
    } | timeout 60 "$HERE/start.sh" 2>/dev/null | grep '"id":11' || true
  )
  if echo "$RESULT" | grep -q '"count"'; then
    ok "knowledge_search returned a count field"
  else
    fail "knowledge_search produced no count field: ${RESULT:0:200}"
  fi
else
  echo "[5] e2e skipped (set E2E=1 to run)"
fi

# ----------------------------------------------------------------------------

echo
if [ "$FAIL" -eq 0 ]; then
  green "$PASS/$((PASS+FAIL)) passed"
  exit 0
else
  red "$FAIL failed, $PASS passed"
  exit 1
fi
