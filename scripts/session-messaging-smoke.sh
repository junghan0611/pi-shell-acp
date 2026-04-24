#!/usr/bin/env bash
# session-messaging-smoke.sh — send_to_session 4-case matrix.
#
# Verifies the Cross-Session Messaging surface described in
# AGENTS.md § Entwurf Orchestration § Cross-Session Messaging.
#
# Matrix (per GLG's 3-matrix + baseline):
#   case 1: native sender → ACP-provider target      ← user's case ①
#   case 2: MCP sender    → native target            ← user's case ②
#   case 3: MCP sender    → ACP-provider target      ← user's case ③
#   case 4: native sender → native target            ← baseline
#
# Sender surfaces:
#   native — pi's control.ts CLI bridge
#            (pi -p --session-control --control-session <id> --send-session-message ...)
#   MCP    — pi-tools-bridge stdio JSON-RPC (tools/call send_to_session)
#
# Targets are pi sessions with --session-control. "ACP" here means the target
# pi uses pi-shell-acp as its LLM provider — the control socket namespace
# (~/.pi/session-control/) is unified across providers. Targets are spawned
# in disposable tmux sessions and killed on exit.
#
# Cost: ACP target bootstrap incurs a small Claude-token charge
# (~$0.01–0.05). Native target uses a mini Codex model.
#
# Usage: scripts/session-messaging-smoke.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$REPO/mcp/pi-tools-bridge/start.sh"
CONTROL_DIR="$HOME/.pi/session-control"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARTIFACT="${SMS_ARTIFACT:-/tmp/session-messaging-smoke-$TIMESTAMP.json}"
BOOT_TIMEOUT="${SMS_BOOT_TIMEOUT:-30}"

NATIVE_PROVIDER="openai-codex"
NATIVE_MODEL="gpt-5.4-mini"
ACP_PROVIDER="pi-shell-acp"
ACP_MODEL="claude-sonnet-4-6"

TMUX_N="sms-tgt-n-$$"
TMUX_A="sms-tgt-a-$$"

pass=0
fail=0
RESULTS_JSON=""
TGT_N=""
TGT_A=""

log() { printf '[sms] %s\n' "$*" >&2; }

cleanup() {
  tmux kill-session -t "$TMUX_N" 2>/dev/null || true
  tmux kill-session -t "$TMUX_A" 2>/dev/null || true
}
trap cleanup EXIT

snapshot_sockets() {
  ls "$CONTROL_DIR"/*.sock 2>/dev/null | sort
}

# wait for a new socket to appear after starting a pi in tmux.
# echoes the new session id (basename without .sock) on success.
wait_for_new_socket() {
  local before="$1" i
  for i in $(seq 1 "$BOOT_TIMEOUT"); do
    local now new
    now=$(snapshot_sockets)
    new=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$now") | head -1)
    if [ -n "$new" ]; then
      basename "$new" .sock
      return 0
    fi
    sleep 1
  done
  return 1
}

record() {
  local name="$1" status="$2" evidence="$3"
  evidence=${evidence//\"/\\\"}
  if [ -n "$RESULTS_JSON" ]; then RESULTS_JSON+=","; fi
  RESULTS_JSON+=$'\n'"    {\"case\":\"$name\",\"status\":\"$status\",\"evidence\":\"$evidence\"}"
  if [ "$status" = "PASS" ]; then
    pass=$((pass+1))
    printf '  \033[32m✓\033[0m %-24s %s\n' "$name" "$evidence"
  else
    fail=$((fail+1))
    printf '  \033[31m✗\033[0m %-24s %s\n' "$name" "$evidence"
  fi
}

case_native() {
  local case_name="$1" target="$2"
  local out rc
  out=$(timeout 20 pi -p --session-control --control-session "$target" \
        --send-session-message "sms:$case_name" \
        --send-session-mode follow_up \
        --send-session-wait message_processed 2>&1 | tail -1)
  rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q "message processed"; then
    record "$case_name" "PASS" "$out"
  else
    record "$case_name" "FAIL" "rc=$rc out=$out"
  fi
}

case_mcp() {
  local case_name="$1" target="$2"
  local raw parsed err evidence
  raw=$({
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"sms","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"send_to_session\",\"arguments\":{\"target\":\"$target\",\"message\":\"sms:$case_name\"}}}"
    sleep 2
  } | timeout 15 "$BRIDGE" 2>/dev/null | grep '"id":2')
  parsed=$(printf '%s' "$raw" | python3 -c '
import json, sys
try:
  d=json.loads(sys.stdin.read())
  r=d["result"]
  err=r.get("isError")
  text=r["content"][0]["text"]
  print(f"{err}|{text[:200]}")
except Exception as e:
  print(f"PARSE_ERR|{e}")' 2>/dev/null)
  err="${parsed%%|*}"
  evidence="${parsed#*|}"
  if [ "$err" != "True" ] && [ "$err" != "PARSE_ERR" ] && echo "$evidence" | grep -q "delivered"; then
    record "$case_name" "PASS" "$evidence"
  else
    record "$case_name" "FAIL" "isError=$err evidence=$evidence"
  fi
}

log "artifact: $ARTIFACT"
log "bridge:   $BRIDGE"
log "control:  $CONTROL_DIR"
echo

log "→ Target-N (native: $NATIVE_PROVIDER/$NATIVE_MODEL) in tmux $TMUX_N"
pre=$(snapshot_sockets)
tmux new -d -s "$TMUX_N" "pi --session-control --provider $NATIVE_PROVIDER --model $NATIVE_MODEL" \
  || { log "FATAL: tmux new Target-N failed"; exit 1; }
TGT_N=$(wait_for_new_socket "$pre") || { log "FATAL: Target-N socket did not appear in ${BOOT_TIMEOUT}s"; exit 1; }
log "  Target-N: $TGT_N"

log "→ Target-A (ACP: $ACP_PROVIDER/$ACP_MODEL) in tmux $TMUX_A"
pre=$(snapshot_sockets)
tmux new -d -s "$TMUX_A" "pi --session-control --provider $ACP_PROVIDER --model $ACP_MODEL" \
  || { log "FATAL: tmux new Target-A failed"; exit 1; }
TGT_A=$(wait_for_new_socket "$pre") || { log "FATAL: Target-A socket did not appear in ${BOOT_TIMEOUT}s"; exit 1; }
log "  Target-A: $TGT_A"

echo
log "running 4-case matrix:"
case_native "native→ACP"    "$TGT_A"   # user's case ①
case_mcp    "mcp→native"    "$TGT_N"   # user's case ②
case_mcp    "mcp→ACP"       "$TGT_A"   # user's case ③
case_native "native→native" "$TGT_N"   # baseline

echo
if [ "$fail" -eq 0 ]; then
  printf '\033[32m%d/%d PASS\033[0m — wire compatibility verified across both sender surfaces × both target providers\n' \
    "$pass" "$((pass+fail))"
else
  printf '\033[31m%d PASS / %d FAIL\033[0m\n' "$pass" "$fail"
fi

cat > "$ARTIFACT" <<EOF
{
  "generatedAt": "$(date -Iseconds -u | sed 's/+00:00/Z/')",
  "pass": $pass,
  "fail": $fail,
  "targets": {
    "native": { "sessionId": "$TGT_N", "provider": "$NATIVE_PROVIDER", "model": "$NATIVE_MODEL" },
    "acp":    { "sessionId": "$TGT_A", "provider": "$ACP_PROVIDER",    "model": "$ACP_MODEL"    }
  },
  "cases": [$RESULTS_JSON
  ]
}
EOF
log "wrote artifact: $ARTIFACT"

[ "$fail" -eq 0 ] || exit 1
exit 0
