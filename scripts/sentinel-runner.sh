#!/usr/bin/env bash
# sentinel-runner.sh — 6-cell delegate matrix sentinel.
#
# Covers the high-risk diagonal slice of parent_surface × target before
# committing to a full 18-cell positive matrix. Each cell runs:
#   spawn:  parent pi → delegate(task, provider, model, mode=sync)
#   resume: parent pi → delegate_resume(taskId, prompt)
# and asserts structural evidence only — never the parent model's
# natural-language echo. Evidence comes from two sources:
#   1. raw `pi --mode json` stdout (for Task ID extraction)
#   2. the delegate's session JSONL (for turn count, identity, cost)
#
# Usage:
#   scripts/sentinel-runner.sh                 # all 6 cells
#   scripts/sentinel-runner.sh 1,3,5           # subset by id
#   scripts/sentinel-runner.sh --help
#
# Env overrides:
#   SENTINEL_ARTIFACT — final JSON path (default: /tmp/sentinel-<ts>.json)
#   SENTINEL_TIMEOUT  — per-pi-call timeout seconds (default: 240)
#   SENTINEL_WAIT     — resume polling budget seconds (default: 180)
#   REPOS             — ~/repos/gh root (default: $HOME/repos/gh)
#
# Scope (this round, per PM): sync spawn + resume only. Out of scope:
#   - opus / mini target positive coverage
#   - async completion matrix
#   - remote/SSH
#   - full 18/18

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="${REPOS:-$HOME/repos/gh}"
SESSIONS_BASE="$HOME/.pi/agent/sessions"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARTIFACT="${SENTINEL_ARTIFACT:-/tmp/sentinel-${TIMESTAMP}.json}"
TIMEOUT="${SENTINEL_TIMEOUT:-240}"
WAIT_BUDGET="${SENTINEL_WAIT:-180}"
LOG_DIR="/tmp/sentinel-${TIMESTAMP}"
mkdir -p "$LOG_DIR"

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_GRAY=$'\033[90m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_GRAY=''; C_BOLD=''; C_RESET=''
fi

log() { printf '[sentinel] %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
sentinel-runner.sh — 6-cell delegate matrix sentinel

Usage: scripts/sentinel-runner.sh [cells]

Arguments:
  cells    comma-separated cell ids (1..6). Omit for all.

Environment:
  SENTINEL_ARTIFACT   JSON output path (default: /tmp/sentinel-<ts>.json)
  SENTINEL_TIMEOUT    per-pi-call timeout seconds (default: 240)
  SENTINEL_WAIT       resume polling budget seconds (default: 180)

Cells:
  1  native          → openai-codex/gpt-5.2
  2  native          → pi-shell-acp/claude-sonnet-4-6
  3  native          → pi-shell-acp/gpt-5.2 (explicitOnly)
  4  acp-claude      → openai-codex/gpt-5.2
  5  acp-claude      → pi-shell-acp/gpt-5.2 (explicitOnly)
  6  acp-codex       → openai-codex/gpt-5.2

Failure codes:
  S1 parent non-zero exit            (spawn stage)
  S2 no "Task ID:" in raw stream
  S3 session file not found for taskId
  S4 session has no assistant turn
  S5 identity mismatch (lastModel vs target)
  S6 bridge path != new             (child stderr, ACP-target only)
  R1 parent non-zero exit            (resume stage)
  R2 turns did not increase within SENTINEL_WAIT
  R3 identity drift on resume (lastModel changed)
  R4 bridge path != resume|load      (child stderr, ACP-target only)
  R5 semantic recall missed          (token not in last assistant turn)
EOF
}

# ----------------------------------------------------------------------------
# Prompt hygiene — 운영 룰 (2026-04-23 wording 오염 사건 교훈)
#
# 두 층은 별개다. 한 층의 통과를 다른 층의 통과로 외삽하지 말 것:
#   - bridge continuity : child stderr `[pi-shell-acp:bootstrap]` path=resume|load
#   - semantic continuity : 이전 turn의 사실을 다음 turn에서 회수
#
# 기억 토큰 선택 규칙:
#   - 반드시 의미 중립 명사(동물/식물/자연/사물). 문화·정치 함의 없는 것.
#   - 금지: "test-token-*", "password", "secret", "api key",
#           "credential", 영숫자 식별자 형태 전반. safety 해석을 유발함.
#   - 첫 turn 응답은 짧은 ack(READY)로 강제해 모델이 산만해지지 않게.
# ----------------------------------------------------------------------------
TOKEN_POOL=(올빼미 해바라기 단풍나무 갈대 벚꽃 호수 구름 바다 사슴 고래 보름달 소나무 매화 등불 돌탑)
pick_token() {
  echo "${TOKEN_POOL[$(( RANDOM % ${#TOKEN_POOL[@]} ))]}"
}

# ----------------------------------------------------------------------------
# Cell registry
# id|parent_key|target_provider|target_model
# ----------------------------------------------------------------------------
ALL_CELLS=(
  "1|native|openai-codex|gpt-5.2"
  "2|native|pi-shell-acp|claude-sonnet-4-6"
  "3|native|pi-shell-acp|gpt-5.2"
  "4|acp-claude|openai-codex|gpt-5.2"
  "5|acp-claude|pi-shell-acp|gpt-5.2"
  "6|acp-codex|openai-codex|gpt-5.2"
)

# ----------------------------------------------------------------------------
# Parent spawn — runs pi with the chosen parent surface, captures stdout.
# Uses `pi --mode json` so the tool_result payloads reach stdout verbatim,
# giving us a paraphrase-free anchor for `Task ID: <8hex>`.
#
# child_stderr_log (4th arg, optional): when set, exported to the parent pi as
# PI_DELEGATE_CHILD_STDERR_LOG so delegate-core's mirrorChildStderr() appends
# the delegate child's stderr to that file. This is the only way to observe
# child-side `[pi-shell-acp:bootstrap]` bridge markers — parent stderr can't
# see the bridge when target provider is pi-shell-acp (bridge lives in child).
# ----------------------------------------------------------------------------
parent_spawn() {
  local parent_key="$1" prompt="$2" out_file="$3" child_stderr_log="${4:-}"
  if [ -n "$child_stderr_log" ]; then
    export PI_DELEGATE_CHILD_STDERR_LOG="$child_stderr_log"
  else
    unset PI_DELEGATE_CHILD_STDERR_LOG
  fi
  case "$parent_key" in
    native)
      # --no-extensions -e delegate.ts: load only our delegate tool. This is the
      # same pattern as validate_pi_native_async_delegate and avoids accidental
      # cross-loads from global extensions.
      timeout "$TIMEOUT" pi --mode json -p --no-extensions \
        -e "$SCRIPT_DIR/pi-extensions/delegate.ts" \
        --provider openai-codex --model gpt-5.4-mini \
        "$prompt" >"$out_file" 2>&1
      ;;
    acp-claude)
      # ACP parent brings pi-tools-bridge MCP into scope (per validate_pi_tools_bridge_backend).
      # The MCP delegate/delegate_resume tools are what the parent will invoke.
      timeout "$TIMEOUT" pi --mode json -p \
        -e "$REPOS/pi-shell-acp" \
        --provider pi-shell-acp --model claude-sonnet-4-6 \
        "$prompt" >"$out_file" 2>&1
      ;;
    acp-codex)
      timeout "$TIMEOUT" pi --mode json -p \
        -e "$REPOS/pi-shell-acp" \
        --provider pi-shell-acp --model gpt-5.2 \
        "$prompt" >"$out_file" 2>&1
      ;;
    *)
      log "unknown parent_key: $parent_key"
      return 2 ;;
  esac
}

# ----------------------------------------------------------------------------
# Prompts. Deliberately terse: we only need the model to call the tool once.
# The model's post-call prose is irrelevant — we read raw JSON and session JSONL.
#
# The spawn task plants a neutral memory token and asks the child for a fixed
# ack (READY). The resume task asks the child to recall the token in one word.
# Token neutrality + short ack protects the check from safety-filter contamination
# (see Prompt hygiene rules at the top of this file).
# ----------------------------------------------------------------------------
build_spawn_prompt() {
  local provider="$1" model="$2" token="$3"
  printf 'delegate 도구를 정확히 1회 호출하라. 인수: { task: "기억 단어는 %s 다. READY 한 단어만 답해라.", provider: "%s", model: "%s", mode: "sync" }. 도구 호출이 끝나면 설명이나 요약 없이 즉시 턴을 종료하라.' \
    "$token" "$provider" "$model"
}

build_resume_prompt() {
  local task_id="$1"
  printf 'delegate_resume 도구를 정확히 1회 호출하라. 인수: { taskId: "%s", prompt: "기억 단어를 한 단어로만 답해라." }. 도구 호출이 끝나면 설명이나 요약 없이 즉시 턴을 종료하라.' \
    "$task_id"
}

# ----------------------------------------------------------------------------
# Evidence extraction
# ----------------------------------------------------------------------------
# Task ID appears verbatim in the tool_result content of the delegate tool
# response (see formatSyncSummary / async spawn). Grepping the raw --mode json
# stream is paraphrase-proof.
extract_task_id() {
  grep -oE 'Task ID: [a-f0-9]{8}' "$1" | head -1 | awk '{print $3}'
}

find_session_file() {
  local task_id="$1"
  find "$SESSIONS_BASE" -type f -name "*delegate-${task_id}*.jsonl" 2>/dev/null | head -1
}

# S2 fallback: find the most recent delegate-*.jsonl created after $1 (epoch).
# Needed when the parent surface does not echo tool_result text into the raw
# --mode json assistant content (observed with ACP Codex parent, where
# `[tool:done]` is emitted but the structured result lives outside the
# captured content stream). The filesystem is the ground truth — a new
# session file means the spawn did reach the delegate core.
# Emits: "<taskId>\t<session_file>" on stdout, empty on miss.
find_new_delegate_session() {
  local threshold_ts="$1"
  local newest
  newest=$(find "$SESSIONS_BASE" -type f -name '*delegate-*.jsonl' \
           -newermt "@$threshold_ts" 2>/dev/null |
           xargs -r -I{} stat -c '%Y {}' "{}" 2>/dev/null |
           sort -nr | head -1 | awk '{ $1=""; sub(/^ /, ""); print }')
  [ -z "$newest" ] && return 1
  local tid
  tid=$(basename "$newest" | grep -oE 'delegate-[a-f0-9]{8}' | head -1 | sed 's/^delegate-//')
  [ -z "$tid" ] && return 1
  printf '%s\t%s\n' "$tid" "$newest"
}

# Analyze a delegate session JSONL and emit {turns, cost, lastModel, lastProvider, lastStopReason, lastError}.
# Matches analyzeSessionFileLike in delegate-core.ts — we deliberately re-implement here to keep
# the sentinel free of module-resolution concerns (no TS build dependency).
analyze_session() {
  SENTINEL_FILE="$1" node -e '
const fs = require("fs");
const f = process.env.SENTINEL_FILE;
let turns = 0, cost = 0;
let lastModel = "", lastProvider = "", lastStopReason = "", lastError = "";
try {
  const content = fs.readFileSync(f, "utf-8");
  for (const line of content.trim().split("\n")) {
    try {
      const e = JSON.parse(line);
      if (e.type !== "message" || e.message?.role !== "assistant") continue;
      turns++;
      if (typeof e.message.model === "string") lastModel = e.message.model;
      if (typeof e.message.provider === "string") lastProvider = e.message.provider;
      if (typeof e.message.stopReason === "string") lastStopReason = e.message.stopReason;
      if (typeof e.message.errorMessage === "string" && e.message.errorMessage.trim())
        lastError = e.message.errorMessage.trim();
      const c = e.message.usage?.cost?.total;
      if (typeof c === "number") cost += c;
    } catch {}
  }
} catch (e) {
  lastError = "read_error:" + (e instanceof Error ? e.message : String(e));
}
console.log(JSON.stringify({turns, cost, lastModel, lastProvider, lastStopReason, lastError}));
'
}

# Sum the parent pi's assistant-turn cost by walking its --mode json stdout.
parent_cost() {
  SENTINEL_FILE="$1" node -e '
const fs = require("fs");
let cost = 0;
try {
  const content = fs.readFileSync(process.env.SENTINEL_FILE, "utf-8");
  for (const line of content.split("\n")) {
    try {
      const e = JSON.parse(line);
      if (e.type === "message_end" && e.message?.role === "assistant") {
        const c = e.message.usage?.cost?.total;
        if (typeof c === "number") cost += c;
      }
    } catch {}
  }
} catch {}
console.log(cost);
'
}

# Poll the session file until turns exceed `target`, up to WAIT_BUDGET seconds.
# Returns the final analyze_session JSON on stdout. Exit code 0 = turns grew,
# 1 = budget exhausted (but we still emit the last reading so R2 can report it).
wait_for_turns_gt() {
  local session_file="$1" target="$2"
  local elapsed=0 analysis turns
  while [ "$elapsed" -lt "$WAIT_BUDGET" ]; do
    analysis=$(analyze_session "$session_file")
    turns=$(echo "$analysis" | jq -r '.turns')
    if [ "$turns" -gt "$target" ]; then
      echo "$analysis"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  analyze_session "$session_file"
  return 1
}

# Last assistant turn's textual content from a delegate session JSONL.
# Used for semantic recall assertion (R5). We concatenate text blocks only.
last_assistant_text() {
  SENTINEL_FILE="$1" node -e '
const fs = require("fs");
const f = process.env.SENTINEL_FILE;
let last = "";
try {
  const content = fs.readFileSync(f, "utf-8");
  for (const line of content.trim().split("\n")) {
    try {
      const e = JSON.parse(line);
      if (e.type !== "message" || e.message?.role !== "assistant") continue;
      const c = e.message.content;
      if (typeof c === "string") { last = c; continue; }
      if (Array.isArray(c)) {
        const text = c.filter(b => b && b.type === "text").map(b => b.text || "").join("\n").trim();
        if (text) last = text;
      }
    } catch {}
  }
} catch {}
console.log(last);
'
}

# Bridge continuity anchor — grep the child stderr mirror for pi-shell-acp's
# bootstrap marker. Returns the path= value (new|resume|load|invalidated) or
# empty if no marker is present.
bridge_path_from_log() {
  local log="$1"
  [ -f "$log" ] || return 0
  grep -oE '^\[pi-shell-acp:bootstrap\] path=[a-z-]+' "$log" | tail -1 | sed 's/^.*path=//'
}

# Identity pass: session's recorded model equals the registry target,
# modulo the known ACP prefix stripping. See PM-confirmed normalization:
#   openai-codex/X   → session may record "X" or "openai-codex/X"
#   pi-shell-acp/X   → session records bare "X" (ACP strips provider prefix)
identity_matches() {
  local tp="$1" tm="$2" session_model="$3"
  [ "$session_model" = "$tm" ] && return 0
  [ "$session_model" = "${tp}/${tm}" ] && return 0
  return 1
}

# ----------------------------------------------------------------------------
# Per-cell execution. Globals declared here serve as the payload carried into
# finalize_cell via bash dynamic scoping (local vars visible to called funcs).
# ----------------------------------------------------------------------------
declare -a RESULTS_JSON=()
PASS_COUNT=0
FAIL_COUNT=0

run_cell() {
  local CELL_ID="$1" CELL_PARENT="$2" CELL_TP="$3" CELL_TM="$4"
  local CELL_STATUS="FAIL" CELL_FCODE="" CELL_NOTE=""
  local SPAWN_TASK_ID="" SPAWN_SESSION=""
  local SPAWN_TURNS=0 SPAWN_PROV="" SPAWN_MODEL="" SPAWN_STOP="" SPAWN_COST=0
  local RESUME_TB=0 RESUME_TA=0 RESUME_PROV="" RESUME_MODEL="" RESUME_STOP="" RESUME_COST=0
  local PARENT_COST=0
  # Per-cell neutral token for semantic recall (R5). Fresh each cell so we
  # can't accidentally pass via cached state from a prior run.
  local CELL_TOKEN
  CELL_TOKEN=$(pick_token)
  # Whether this cell's delegate child uses pi-shell-acp bridge — decides
  # if S6/R4 bridge-path anchors apply. Only ACP target provider qualifies;
  # native target provider means no bridge in the child.
  local CELL_BRIDGE_CHILD=0
  [ "$CELL_TP" = "pi-shell-acp" ] && CELL_BRIDGE_CHILD=1
  # For Codex via ACP the second-load path is "load" (persisted state hydrate),
  # for Claude via ACP it is "resume" (live ACP session reuse). See pi-shell-acp
  # smoke-continuity for the canonical mapping.
  local CELL_EXPECTED_RESUME_PATH=""
  if [ "$CELL_BRIDGE_CHILD" -eq 1 ]; then
    case "$CELL_TM" in
      claude-*) CELL_EXPECTED_RESUME_PATH="resume" ;;
      gpt-*)    CELL_EXPECTED_RESUME_PATH="load" ;;
      *)        CELL_EXPECTED_RESUME_PATH="resume" ;;
    esac
  fi

  printf '%s▶ cell %s: parent=%s → %s/%s  token=%s%s\n' \
    "$C_BOLD" "$CELL_ID" "$CELL_PARENT" "$CELL_TP" "$CELL_TM" "$CELL_TOKEN" "$C_RESET" >&2

  # --- Spawn stage --------------------------------------------------------
  local spawn_prompt spawn_log="$LOG_DIR/cell${CELL_ID}-spawn.log"
  local spawn_child_log="$LOG_DIR/cell${CELL_ID}-spawn-child.log"
  spawn_prompt=$(build_spawn_prompt "$CELL_TP" "$CELL_TM" "$CELL_TOKEN")

  # Snapshot the pre-spawn wall clock (minus a second for race safety).
  # Used by the S2 fallback to find a freshly-created delegate session file
  # if the parent's raw stream doesn't carry the Task ID text.
  local spawn_threshold=$(( $(date +%s) - 1 ))

  local rc=0
  parent_spawn "$CELL_PARENT" "$spawn_prompt" "$spawn_log" "$spawn_child_log" || rc=$?
  if [ "$rc" -ne 0 ]; then
    CELL_FCODE="S1"
    CELL_NOTE="parent exit rc=$rc (timeout or crash) — see $spawn_log"
    finalize_cell; return
  fi

  SPAWN_TASK_ID=$(extract_task_id "$spawn_log")
  if [ -z "$SPAWN_TASK_ID" ]; then
    # S2 fallback — parent surfaces that don't echo tool_result into their
    # raw stream (ACP Codex) still write a session file. The fs is truth.
    local fb
    if fb=$(find_new_delegate_session "$spawn_threshold"); then
      SPAWN_TASK_ID="${fb%%$'\t'*}"
      SPAWN_SESSION="${fb##*$'\t'}"
      log "  [fallback] taskId=$SPAWN_TASK_ID from session-file delta"
    fi
  fi

  if [ -z "$SPAWN_TASK_ID" ]; then
    CELL_FCODE="S2"
    CELL_NOTE="no 'Task ID:' in raw stream and no new delegate session file after parent exit — see $spawn_log"
    finalize_cell; return
  fi
  log "  spawn taskId=$SPAWN_TASK_ID"

  # Reuse session file from fallback if already resolved; otherwise look it up.
  if [ -z "$SPAWN_SESSION" ]; then
    SPAWN_SESSION=$(find_session_file "$SPAWN_TASK_ID")
  fi
  if [ -z "$SPAWN_SESSION" ] || [ ! -f "$SPAWN_SESSION" ]; then
    CELL_FCODE="S3"
    CELL_NOTE="no session JSONL found for delegate-$SPAWN_TASK_ID under $SESSIONS_BASE"
    finalize_cell; return
  fi

  local spawn_analysis
  spawn_analysis=$(analyze_session "$SPAWN_SESSION")
  SPAWN_TURNS=$(echo "$spawn_analysis" | jq -r '.turns')
  SPAWN_PROV=$(echo "$spawn_analysis" | jq -r '.lastProvider')
  SPAWN_MODEL=$(echo "$spawn_analysis" | jq -r '.lastModel')
  SPAWN_STOP=$(echo "$spawn_analysis" | jq -r '.lastStopReason')
  SPAWN_COST=$(echo "$spawn_analysis" | jq -r '.cost')

  if [ "${SPAWN_TURNS:-0}" -lt 1 ]; then
    CELL_FCODE="S4"
    CELL_NOTE="session has 0 assistant turns — delegate never reached a message_end"
    finalize_cell; return
  fi

  if ! identity_matches "$CELL_TP" "$CELL_TM" "$SPAWN_MODEL"; then
    CELL_FCODE="S5"
    CELL_NOTE="expected model=$CELL_TM (or $CELL_TP/$CELL_TM), session recorded lastModel=$SPAWN_MODEL"
    finalize_cell; return
  fi

  # Bridge continuity on spawn (ACP-target only): child's pi-shell-acp should
  # announce path=new for the fresh session. If missing or different, the
  # bridge did not engage as expected.
  if [ "$CELL_BRIDGE_CHILD" -eq 1 ]; then
    local spawn_bridge_path
    spawn_bridge_path=$(bridge_path_from_log "$spawn_child_log")
    if [ "$spawn_bridge_path" != "new" ]; then
      CELL_FCODE="S6"
      CELL_NOTE="bridge spawn path expected=new, got=${spawn_bridge_path:-<absent>} — see $spawn_child_log"
      finalize_cell; return
    fi
  fi

  # --- Resume stage -------------------------------------------------------
  RESUME_TB="$SPAWN_TURNS"
  local resume_prompt resume_log="$LOG_DIR/cell${CELL_ID}-resume.log"
  local resume_child_log="$LOG_DIR/cell${CELL_ID}-resume-child.log"
  resume_prompt=$(build_resume_prompt "$SPAWN_TASK_ID")

  rc=0
  parent_spawn "$CELL_PARENT" "$resume_prompt" "$resume_log" "$resume_child_log" || rc=$?
  if [ "$rc" -ne 0 ]; then
    CELL_FCODE="R1"
    CELL_NOTE="resume parent exit rc=$rc — see $resume_log"
    finalize_cell; return
  fi

  # Native parent's delegate_resume is async (see pi-extensions/delegate.ts
  # registerTool('delegate_resume')). ACP parent routes through the MCP
  # bridge's runDelegateResumeSync which is blocking. Poll uniformly to
  # cover both: wait for session turns to exceed the pre-resume snapshot.
  local resume_analysis
  if resume_analysis=$(wait_for_turns_gt "$SPAWN_SESSION" "$RESUME_TB"); then
    :
  else
    CELL_FCODE="R2"
    RESUME_TA=$(echo "$resume_analysis" | jq -r '.turns')
    CELL_NOTE="turns did not increase within ${WAIT_BUDGET}s (before=$RESUME_TB, after=$RESUME_TA)"
    RESUME_PROV=$(echo "$resume_analysis" | jq -r '.lastProvider')
    RESUME_MODEL=$(echo "$resume_analysis" | jq -r '.lastModel')
    RESUME_STOP=$(echo "$resume_analysis" | jq -r '.lastStopReason')
    RESUME_COST=$(echo "$resume_analysis" | jq -r '.cost')
    finalize_cell; return
  fi

  RESUME_TA=$(echo "$resume_analysis" | jq -r '.turns')
  RESUME_PROV=$(echo "$resume_analysis" | jq -r '.lastProvider')
  RESUME_MODEL=$(echo "$resume_analysis" | jq -r '.lastModel')
  RESUME_STOP=$(echo "$resume_analysis" | jq -r '.lastStopReason')
  RESUME_COST=$(echo "$resume_analysis" | jq -r '.cost')

  # Identity preservation: lastModel must not drift between spawn and resume.
  # This is tighter than "matches target" — we want the EXACT recorded identity
  # to survive across the resume.
  if [ "$RESUME_MODEL" != "$SPAWN_MODEL" ]; then
    CELL_FCODE="R3"
    CELL_NOTE="identity drift: spawn recorded $SPAWN_MODEL, resume recorded $RESUME_MODEL"
    finalize_cell; return
  fi

  # Bridge continuity on resume (ACP-target only): child's pi-shell-acp must
  # announce path=resume (Claude) or path=load (Codex). Anything else — new,
  # invalidated, absent — means the bridge did not reconnect the session and
  # we're seeing structural turn growth over a freshly replayed history rather
  # than true continuity. R3 identity check alone cannot distinguish these.
  if [ "$CELL_BRIDGE_CHILD" -eq 1 ]; then
    local resume_bridge_path
    resume_bridge_path=$(bridge_path_from_log "$resume_child_log")
    if [ "$resume_bridge_path" != "$CELL_EXPECTED_RESUME_PATH" ]; then
      CELL_FCODE="R4"
      CELL_NOTE="bridge resume path expected=$CELL_EXPECTED_RESUME_PATH, got=${resume_bridge_path:-<absent>} — see $resume_child_log"
      finalize_cell; return
    fi
  fi

  # Semantic continuity: the token planted on spawn must appear in the last
  # assistant turn after resume. This is the layer that R2/R3 cannot cover
  # (a cache-miss replay can still pass R2/R3). Neutral token + short ack
  # prompt design — see Prompt hygiene rules at top of file.
  local last_text
  last_text=$(last_assistant_text "$SPAWN_SESSION")
  if [[ "$last_text" != *"$CELL_TOKEN"* ]]; then
    CELL_FCODE="R5"
    CELL_NOTE="semantic recall missed: token='$CELL_TOKEN' not in last assistant turn — got: ${last_text:0:120}"
    finalize_cell; return
  fi

  CELL_STATUS="PASS"
  CELL_FCODE=""
  finalize_cell
}

finalize_cell() {
  PARENT_COST=$(
    {
      [ -s "$LOG_DIR/cell${CELL_ID}-spawn.log" ] && parent_cost "$LOG_DIR/cell${CELL_ID}-spawn.log"
      [ -s "$LOG_DIR/cell${CELL_ID}-resume.log" ] && parent_cost "$LOG_DIR/cell${CELL_ID}-resume.log"
    } | jq -s 'add // 0'
  )

  if [ "$CELL_STATUS" = "PASS" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '%s  ✓ cell %s PASS — turns %d→%d, model=%s%s\n' \
      "$C_GREEN" "$CELL_ID" "$RESUME_TB" "$RESUME_TA" "$RESUME_MODEL" "$C_RESET" >&2
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '%s  ✗ cell %s FAIL [%s] — %s%s\n' \
      "$C_RED" "$CELL_ID" "$CELL_FCODE" "$CELL_NOTE" "$C_RESET" >&2
  fi

  local json
  json=$(
    CELL_ID="$CELL_ID" CELL_PARENT="$CELL_PARENT" CELL_TP="$CELL_TP" CELL_TM="$CELL_TM" \
    CELL_STATUS="$CELL_STATUS" CELL_FCODE="$CELL_FCODE" CELL_NOTE="$CELL_NOTE" \
    SPAWN_TASK_ID="$SPAWN_TASK_ID" SPAWN_SESSION="$SPAWN_SESSION" \
    SPAWN_TURNS="$SPAWN_TURNS" SPAWN_PROV="$SPAWN_PROV" SPAWN_MODEL="$SPAWN_MODEL" \
    SPAWN_STOP="$SPAWN_STOP" SPAWN_COST="$SPAWN_COST" \
    RESUME_TB="$RESUME_TB" RESUME_TA="$RESUME_TA" \
    RESUME_PROV="$RESUME_PROV" RESUME_MODEL="$RESUME_MODEL" \
    RESUME_STOP="$RESUME_STOP" RESUME_COST="$RESUME_COST" \
    PARENT_COST="$PARENT_COST" \
    SPAWN_LOG="$LOG_DIR/cell${CELL_ID}-spawn.log" \
    RESUME_LOG="$LOG_DIR/cell${CELL_ID}-resume.log" \
    node -e '
const env = process.env;
const num = (k) => { const v = env[k]; if (!v) return 0; const n = Number(v); return Number.isFinite(n) ? n : 0; };
const str = (k) => (env[k] && env[k].length) ? env[k] : null;
const obj = {
  cellId: str("CELL_ID"),
  parentSurface: str("CELL_PARENT"),
  target: { provider: str("CELL_TP"), model: str("CELL_TM") },
  status: str("CELL_STATUS"),
  failureCode: str("CELL_FCODE"),
  note: str("CELL_NOTE"),
  spawn: {
    taskId: str("SPAWN_TASK_ID"),
    sessionFile: str("SPAWN_SESSION"),
    turns: num("SPAWN_TURNS"),
    lastProvider: str("SPAWN_PROV"),
    lastModel: str("SPAWN_MODEL"),
    lastStopReason: str("SPAWN_STOP"),
    cost: num("SPAWN_COST"),
    parentLog: str("SPAWN_LOG"),
  },
  resume: {
    turnsBefore: num("RESUME_TB"),
    turnsAfter: num("RESUME_TA"),
    lastProvider: str("RESUME_PROV"),
    lastModel: str("RESUME_MODEL"),
    lastStopReason: str("RESUME_STOP"),
    cost: num("RESUME_COST"),
    parentLog: str("RESUME_LOG"),
  },
  parentCost: num("PARENT_COST"),
  costTotal: num("RESUME_COST") + num("PARENT_COST"),
};
console.log(JSON.stringify(obj));
'
  )
  RESULTS_JSON+=("$json")
}

# ----------------------------------------------------------------------------
# Final reporting: human-readable table + machine-readable JSON artifact.
# ----------------------------------------------------------------------------
print_table() {
  printf '\n%s══════════════════════════════════════════════════════════════════════════════%s\n' \
    "$C_BOLD" "$C_RESET"
  printf '%s Sentinel matrix — %d/%d PASS (artifact: %s)%s\n' \
    "$C_BOLD" "$PASS_COUNT" "$((PASS_COUNT + FAIL_COUNT))" "$ARTIFACT" "$C_RESET"
  printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' \
    "$C_BOLD" "$C_RESET"
  printf '%-3s %-12s %-30s %-9s %-8s %-9s\n' '#' 'parent' 'target' 'spawn' 'resume' 'cost($)'
  printf '%s\n' '─────────────────────────────────────────────────────────────────────────────'
  local obj
  for obj in "${RESULTS_JSON[@]}"; do
    echo "$obj"
  done | jq -r '
    . as $o
    | ($o.failureCode // "") as $fc
    | (if $o.status == "PASS"
         then "✓ \($o.spawn.turns)t"
         else (if ($fc | startswith("S")) then "✗ " + $fc else "✓ \($o.spawn.turns)t" end)
       end) as $sp
    | (if $o.status == "PASS"
         then "✓ +\($o.resume.turnsAfter - $o.resume.turnsBefore)t"
         else (if ($fc | startswith("R")) then "✗ " + $fc
               elif ($fc | startswith("S")) then "-"
               else "?" end)
       end) as $rs
    | [ $o.cellId, $o.parentSurface,
        "\($o.target.provider)/\($o.target.model)",
        $sp, $rs, ($o.costTotal | tostring | .[0:7]) ]
    | @tsv' |
  while IFS=$'\t' read -r id parent target sp rs cost; do
    printf '%-3s %-12s %-30s %-9s %-8s %-9s\n' "$id" "$parent" "$target" "$sp" "$rs" "$cost"
  done

  # Failures detail
  local any_fail=0
  for obj in "${RESULTS_JSON[@]}"; do
    if echo "$obj" | jq -e '.status == "FAIL"' >/dev/null; then
      if [ "$any_fail" -eq 0 ]; then
        printf '\n%sFailure details:%s\n' "$C_BOLD" "$C_RESET"
        any_fail=1
      fi
      echo "$obj" | jq -r '"  cell \(.cellId) [\(.failureCode)]: \(.note)"'
    fi
  done
}

write_artifact() {
  {
    echo '{'
    printf '  "generatedAt": "%s",\n' "$(date -u +%FT%TZ)"
    printf '  "artifactPath": "%s",\n' "$ARTIFACT"
    printf '  "logDir": "%s",\n' "$LOG_DIR"
    printf '  "pass": %d,\n' "$PASS_COUNT"
    printf '  "fail": %d,\n' "$FAIL_COUNT"
    echo '  "cells": ['
    local i
    for i in "${!RESULTS_JSON[@]}"; do
      if [ "$i" -gt 0 ]; then echo ','; fi
      printf '    %s' "${RESULTS_JSON[$i]}"
    done
    echo ''
    echo '  ]'
    echo '}'
  } | jq '.' > "$ARTIFACT"
  log "wrote artifact: $ARTIFACT"
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
  local selection="${1:-all}"
  if [ "$selection" = "--help" ] || [ "$selection" = "-h" ]; then
    usage; exit 0
  fi

  # Sanity: we need pi, jq, node, and the pi-shell-acp repo for ACP cells.
  command -v pi   >/dev/null || { log "missing binary: pi";   exit 2; }
  command -v jq   >/dev/null || { log "missing binary: jq";   exit 2; }
  command -v node >/dev/null || { log "missing binary: node"; exit 2; }

  # Resolve selected cells
  local selected=()
  if [ "$selection" = "all" ]; then
    selected=("${ALL_CELLS[@]}")
  else
    local id
    for id in ${selection//,/ }; do
      local match=""
      for cell in "${ALL_CELLS[@]}"; do
        [ "${cell%%|*}" = "$id" ] && match="$cell" && break
      done
      if [ -z "$match" ]; then
        log "unknown cell id: $id (valid: 1..6)"; exit 2
      fi
      selected+=("$match")
    done
  fi

  log "log dir: $LOG_DIR"
  log "artifact: $ARTIFACT"
  log "running ${#selected[@]} cell(s): $(printf '%s ' "${selected[@]%%|*}")"

  local cell id parent tp tm
  for cell in "${selected[@]}"; do
    IFS='|' read -r id parent tp tm <<<"$cell"
    run_cell "$id" "$parent" "$tp" "$tm"
  done

  print_table
  write_artifact

  if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

main "$@"
