#!/usr/bin/env bash
#
# Model id convention (see AGENTS.md Hard Rule #1):
#   - User-facing examples use the qualified form `pi-shell-acp/<backend-model>`
#     (e.g. `pi-shell-acp/claude-sonnet-4-6`); the prefix routes to this provider
#     so `--provider` is redundant and is dropped in docs.
#   - Smoke helpers that feed `ensureBridgeSession({modelId})` directly (cancel,
#     model-switch) pass BARE backend ids (`claude-sonnet-4-6`, `gpt-5.2`)
#     because the bridge library contract is bare. Smoke helpers that invoke pi
#     via the CLI still pin `--provider pi-shell-acp` and can accept either
#     bare or qualified model, but we keep bare here to match the bridge-level
#     dispatch tables.
#
set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR_DEFAULT=$(pwd)
TARGET_PROJECT_DIR=${2:-$PROJECT_DIR_DEFAULT}
PACKAGE_NAME="pi-shell-acp"
PROVIDER_ID="pi-shell-acp"

usage() {
  cat <<'EOF'
Usage:
  ./run.sh setup [project-dir]        # pnpm install + sync auth + install + smoke-all + Axis 1 gates (bridge, native async, session-messaging, sentinel)
  ./run.sh smoke [project-dir]        # Claude runtime smoke (backward-compatible default)
  ./run.sh smoke-claude [project-dir] # explicit Claude runtime smoke
  ./run.sh smoke-codex [project-dir]  # explicit Codex runtime smoke
  ./run.sh smoke-all [project-dir]    # required dual-backend runtime smoke gate
  ./run.sh smoke-continuity [project-dir] # strict dual-backend persisted bootstrap gate (Claude=resume, Codex=load)
  ./run.sh smoke-cancel [project-dir] # strict cancel/abort cleanup observability gate (Claude + Codex)
  ./run.sh smoke-model-switch [project-dir] # strict dual-backend model switch observability gate (reuse 3 branches)
  ./run.sh smoke-delegate-resume [project-dir] # bridge-level delegate-style continuity gate (Claude=resume, Codex=load)
  ./run.sh smoke-compaction [project-dir] # strict post-compaction handoff gate (Claude recalls pi-side summary token + reuses session)
  ./run.sh check-bridge               # pi-tools-bridge direct MCP smoke + test.sh + ACP visibility/invocation (claude+codex)
  ./run.sh check-native-async         # pi-native async delegate spawn smoke (pi -e pi-extensions/delegate.ts)
  ./run.sh sentinel [args...]         # delegate 6-cell diagonal matrix (sync+resume × parent×target)
  ./run.sh session-messaging [args...] # 4-case session-messaging smoke (native/ACP cross-matrix)
  ./run.sh check-mcp                  # local deterministic check of normalizeMcpServers() — no Claude/ACP subprocess
  ./run.sh check-backends             # local deterministic check of backend launch resolution + backend-specific _meta shape
  ./run.sh check-registration         # local deterministic check of per-runtime provider registration semantics
  ./run.sh check-models               # local deterministic check of MODELS contextWindow cap (default 200K + opt-in override)
  ./run.sh check-compaction-handoff   # local deterministic check of post-compaction summary + kept-turn projection into systemPromptAppend
  ./run.sh check-claude-sessions [project-dir]  # compare pi persisted sessions vs Claude SDK session visibility
  ./run.sh verify-resume [project-dir] # exact pi -> ACP -> Claude continuity check with visible acpSessionId diagnostics
  ./run.sh sync-auth                  # copy ~/.pi/agent/auth.json anthropic OAuth credentials to pi-shell-acp alias
  ./run.sh install [project-dir]      # install this local package into project .pi/settings.json
  ./run.sh remove [project-dir]       # remove pi-shell-acp entries from project .pi/settings.json

Notes:
  - project-dir defaults to current directory
  - Claude Code login should already exist (e.g. ~/.claude.json)
  - smoke-all is the operator-facing dual-backend verification path and is what setup runs
  - API key is optional; this bridge is intended to work with Claude Code auth
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

log()  { echo "  $*"; }
ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠ $*"; }
fail() { echo "  ❌ $*"; }
section() { echo ""; echo "=== $* ==="; }

normalize_project_dir() {
  python3 - "$1" <<'PY'
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
}

sync_auth() {
  local auth_path="$HOME/.pi/agent/auth.json"
  python3 - "$auth_path" "$PROVIDER_ID" <<'PY'
import json, os, sys
from pathlib import Path

auth_path = Path(sys.argv[1]).expanduser()
provider_id = sys.argv[2]
auth_path.parent.mkdir(parents=True, exist_ok=True)

if auth_path.exists():
    data = json.loads(auth_path.read_text())
    if not isinstance(data, dict):
        raise SystemExit("auth.json is not an object")
else:
    data = {}

anthropic = data.get("anthropic")
if not isinstance(anthropic, dict):
    print("sync-auth: skipped (no anthropic OAuth credentials in ~/.pi/agent/auth.json)")
    raise SystemExit(0)

before = json.dumps(data.get(provider_id), sort_keys=True)
after = json.dumps(anthropic, sort_keys=True)
if before == after:
    print(f"sync-auth: already synced ({provider_id})")
    raise SystemExit(0)

data[provider_id] = anthropic
backup = auth_path.with_suffix(auth_path.suffix + ".bak")
if auth_path.exists():
    backup.write_text(auth_path.read_text())
auth_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"sync-auth: wrote {provider_id} alias to {auth_path}")
if backup.exists():
    print(f"sync-auth: backup -> {backup}")
PY
}

install_local_package() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")
  mkdir -p "$project_dir/.pi"
  python3 - "$project_dir/.pi/settings.json" "$REPO_DIR" <<'PY'
import json, sys
from pathlib import Path

settings_path = Path(sys.argv[1])
repo_dir = str(Path(sys.argv[2]).resolve())
settings_path.parent.mkdir(parents=True, exist_ok=True)
if settings_path.exists():
    data = json.loads(settings_path.read_text())
    if not isinstance(data, dict):
        raise SystemExit("settings.json is not an object")
else:
    data = {}

packages = data.get("packages")
if not isinstance(packages, list):
    packages = []

filtered = []
for item in packages:
    source = item.get("source") if isinstance(item, dict) else item
    if isinstance(source, str) and ("pi-shell-acp" in source) and source != repo_dir:
        continue
    filtered.append(item)

if repo_dir not in filtered:
    filtered.append(repo_dir)

data["packages"] = filtered
settings_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"install: updated {settings_path}")
print(f"install: package source -> {repo_dir}")
PY
}

remove_local_package() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")
  python3 - "$project_dir/.pi/settings.json" <<'PY'
import json, sys
from pathlib import Path

settings_path = Path(sys.argv[1])
if not settings_path.exists():
    print(f"remove: nothing to do ({settings_path} missing)")
    raise SystemExit(0)

data = json.loads(settings_path.read_text())
if not isinstance(data, dict):
    raise SystemExit("settings.json is not an object")
packages = data.get("packages")
if not isinstance(packages, list):
    print("remove: nothing to do (packages missing)")
    raise SystemExit(0)

filtered = []
removed = 0
for item in packages:
    source = item.get("source") if isinstance(item, dict) else item
    if isinstance(source, str) and ("pi-shell-acp" in source):
        removed += 1
        continue
    filtered.append(item)

data["packages"] = filtered
settings_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"remove: removed {removed} entries from {settings_path}")
PY
}

smoke_test() {
  local project_dir backend model model_id session_key
  project_dir=$(normalize_project_dir "$1")
  backend=${2:-${PI_SHELL_ACP_BACKEND:-claude}}
  model=${3:-${PI_SHELL_ACP_MODEL:-}}

  if [[ -z "$model" ]]; then
    case "$backend" in
      claude)
        model="pi-shell-acp/claude-sonnet-4-6"
        ;;
      codex)
        model="pi-shell-acp/gpt-5.2"
        ;;
      *)
        echo "[smoke] unknown backend: $backend" >&2
        exit 1
        ;;
    esac
  fi

  model_id=${PI_SHELL_ACP_MODEL_ID:-$model}
  if [[ "$model_id" == "$PROVIDER_ID/"* ]]; then
    model_id=${model_id#${PROVIDER_ID}/}
  fi
  session_key="run-sh-smoke:${backend}:${model_id}"

  require_cmd pi

  echo "[smoke] project:     $project_dir"
  echo "[smoke] repo:        $REPO_DIR"
  echo "[smoke] backend:     $backend"
  echo "[smoke] model:       $model"
  echo "[smoke] model-id:    $model_id"
  echo "[smoke] session-key: $session_key"

  (cd "$project_dir" && pi -e "$REPO_DIR" --list-models pi-shell-acp >/dev/null)
  echo "[smoke] provider models: ok"

  (
    cd "$REPO_DIR"
    PI_SHELL_ACP_SMOKE_BACKEND="$backend" PI_SHELL_ACP_MODEL_ID="$model_id" PI_SHELL_ACP_SMOKE_SESSION_KEY="$session_key" node --input-type=module <<'EOF'
import { ensureBridgeSession, sendPrompt, setActivePromptHandler, closeBridgeSession, normalizeMcpServers } from './acp-bridge.ts';

const sessionKey = process.env.PI_SHELL_ACP_SMOKE_SESSION_KEY || 'run-sh-smoke';
const backend = process.env.PI_SHELL_ACP_SMOKE_BACKEND;
const modelId = process.env.PI_SHELL_ACP_MODEL_ID || 'claude-sonnet-4-6';
if (!backend) {
  throw new Error('PI_SHELL_ACP_SMOKE_BACKEND is required for direct ensureBridgeSession smoke.');
}
const emptyMcpHash = normalizeMcpServers(undefined).hash;
const session = await ensureBridgeSession({
  sessionKey,
  cwd: process.cwd(),
  backend,
  modelId,
  systemPromptAppend: '간단히 답하세요.',
  settingSources: ['user'],
  strictMcpConfig: false,
  mcpServers: [],
  bridgeConfigSignature: JSON.stringify({ backend, appendSystemPrompt: false, settingSources: ['user'], strictMcpConfig: false, mcpServersHash: emptyMcpHash }),
  contextMessageSignatures: [`smoke:${backend}:user:ok만 답하세요.`],
});

let text = '';
setActivePromptHandler(session, (event) => {
  if (event.type !== 'session_notification') return;
  const update = event.notification.update;
  if (update?.sessionUpdate === 'agent_message_chunk' && update.content?.type === 'text') {
    text += update.content.text;
  }
});

const result = await sendPrompt(session, [{ type: 'text', text: 'ok만 답하세요.' }]);
setActivePromptHandler(session, undefined);
await closeBridgeSession(sessionKey);

if (result.stopReason !== 'end_turn') {
  throw new Error(`unexpected stopReason: ${result.stopReason}`);
}
if (!text.trim()) {
  throw new Error('empty bridge response');
}
console.log(`[smoke] bridge response (${backend}/${modelId}): ${text.trim()}`);
EOF
  )
  echo "[smoke] bridge prompt: ok"
}

smoke_all() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")

  echo "[smoke-all] required dual-backend runtime verification starting"
  smoke_test "$project_dir" claude
  smoke_test "$project_dir" codex
  echo "[smoke-all] Claude + Codex runtime smokes: ok"
}

smoke_continuity_single() {
  local project_dir=$1
  local backend=$2
  local model=$3
  local expected_path=$4

  local session_file
  session_file=$(mktemp /tmp/pi-shell-acp-continuity-XXXXXX.jsonl)

  echo "[smoke-continuity/$backend] model=$model expected-turn2=$expected_path session=$session_file"

  local turn1_log
  if ! turn1_log=$(cd "$project_dir" && PI_SHELL_ACP_STRICT_BOOTSTRAP=1 pi -e "$REPO_DIR" --session "$session_file" --provider pi-shell-acp --model "$model" -p 'READY 만 답해' 2>&1); then
    echo "[smoke-continuity/$backend] turn1 pi invocation failed:" >&2
    echo "$turn1_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if ! grep -q "^\[pi-shell-acp:bootstrap\] path=new backend=$backend" <<< "$turn1_log"; then
    echo "[smoke-continuity/$backend] turn1 expected path=new, got:" >&2
    echo "$turn1_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  echo "[smoke-continuity/$backend] turn1 path=new: ok"

  local turn2_log
  if ! turn2_log=$(cd "$project_dir" && PI_SHELL_ACP_STRICT_BOOTSTRAP=1 pi -e "$REPO_DIR" --session "$session_file" --provider pi-shell-acp --model "$model" -p 'OK 만 답해' 2>&1); then
    echo "[smoke-continuity/$backend] turn2 pi invocation failed (strict bootstrap throw?):" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if ! grep -q "^\[pi-shell-acp:bootstrap\] path=$expected_path backend=$backend" <<< "$turn2_log"; then
    echo "[smoke-continuity/$backend] turn2 expected path=$expected_path, got:" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if grep -q "^\[pi-shell-acp:bootstrap-invalidate\]" <<< "$turn2_log"; then
    echo "[smoke-continuity/$backend] turn2 unexpected invalidation on happy continuity:" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  echo "[smoke-continuity/$backend] turn2 path=$expected_path: ok"

  rm -f "$session_file"
}

smoke_continuity() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")

  require_cmd pi

  echo "[smoke-continuity] strict dual-backend persisted bootstrap gate"
  echo "[smoke-continuity] project: $project_dir"
  echo "[smoke-continuity] repo:    $REPO_DIR"

  smoke_continuity_single "$project_dir" claude claude-sonnet-4-6 resume
  smoke_continuity_single "$project_dir" codex gpt-5.2 load
  echo "[smoke-continuity] Claude(resume) + Codex(load) continuity: ok"
}

smoke_cancel_single() {
  local project_dir=$1
  local backend=$2
  local model=$3

  local backend_pattern
  case "$backend" in
    claude) backend_pattern="claude-agent-acp" ;;
    codex)  backend_pattern="codex-acp" ;;
    *)
      echo "[smoke-cancel/$backend] unknown backend" >&2
      exit 1
      ;;
  esac

  echo "[smoke-cancel/$backend] model=$model pattern=$backend_pattern"

  local before
  before=$(pgrep -cf "$backend_pattern" 2>/dev/null) || before=0
  echo "[smoke-cancel/$backend] baseline process count: $before"

  local log_file
  log_file=$(mktemp /tmp/pi-shell-acp-cancel-XXXXXX.log)

  local rc=0
  (
    cd "$REPO_DIR"
    PI_SHELL_ACP_SMOKE_BACKEND="$backend" PI_SHELL_ACP_MODEL_ID="$model" \
      node --input-type=module 2>"$log_file" <<'EOF'
import {
  ensureBridgeSession,
  sendPrompt,
  setActivePromptHandler,
  closeBridgeSession,
  cancelActivePrompt,
  normalizeMcpServers,
} from './acp-bridge.ts';

const backend = process.env.PI_SHELL_ACP_SMOKE_BACKEND;
const modelId = process.env.PI_SHELL_ACP_MODEL_ID;
if (!backend || !modelId) throw new Error('backend/model env required');

const sessionKey = `smoke-cancel:${backend}:${modelId}`;
const emptyMcpHash = normalizeMcpServers(undefined).hash;
const baseParams = {
  sessionKey,
  cwd: process.cwd(),
  backend,
  modelId,
  systemPromptAppend: '간단히 답하세요.',
  settingSources: ['user'],
  strictMcpConfig: false,
  mcpServers: [],
  bridgeConfigSignature: JSON.stringify({
    backend,
    appendSystemPrompt: false,
    settingSources: ['user'],
    strictMcpConfig: false,
    mcpServersHash: emptyMcpHash,
  }),
  contextMessageSignatures: [`smoke-cancel:${backend}`],
};

const session = await ensureBridgeSession(baseParams);

let firstChunkSeen = false;
let cancelled = false;
setActivePromptHandler(session, async (event) => {
  if (event.type !== 'session_notification') return;
  const update = event.notification?.update;
  if (!update) return;
  if (update.sessionUpdate === 'agent_message_chunk' || update.sessionUpdate === 'agent_thought_chunk') {
    if (!firstChunkSeen) {
      firstChunkSeen = true;
      setTimeout(() => {
        if (!cancelled) {
          cancelled = true;
          void cancelActivePrompt(session);
        }
      }, 50);
    }
  }
});

// fallback cancel in case no chunk ever arrives
const failSafe = setTimeout(() => {
  if (!cancelled) {
    cancelled = true;
    void cancelActivePrompt(session);
  }
}, 4000);
failSafe.unref?.();

let longResult;
try {
  longResult = await sendPrompt(session, [{
    type: 'text',
    text: '1부터 300까지 숫자를 하나씩 새 줄에 적어주세요. 각 숫자 옆에 짧은 단어도 하나 붙여주세요.',
  }]);
} catch (error) {
  longResult = { stopReason: 'threw', error: error instanceof Error ? error.message : String(error) };
}
clearTimeout(failSafe);
console.error(`[smoke-cancel] long prompt stopReason=${longResult.stopReason}`);

// session reuse: short prompt must succeed after cancel
setActivePromptHandler(session, () => { /* drop chunks */ });
const reuse = await sendPrompt(session, [{ type: 'text', text: 'ok만 답하세요.' }]);
setActivePromptHandler(session, undefined);
if (reuse.stopReason !== 'end_turn') {
  throw new Error(`reuse failed: stopReason=${reuse.stopReason}`);
}
console.error('[smoke-cancel] session reuse: ok');

await closeBridgeSession(sessionKey, { closeRemote: true, invalidatePersisted: true });
console.error('[smoke-cancel] explicit close: ok');
EOF
  ) || rc=$?

  # drain any late exit
  sleep 1

  if ! grep -q '^\[pi-shell-acp:cancel\]' "$log_file"; then
    echo "[smoke-cancel/$backend] missing [pi-shell-acp:cancel] log line" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  if grep -q '^\[pi-shell-acp:cancel\] .*outcome=failed' "$log_file"; then
    echo "[smoke-cancel/$backend] cancel outcome=failed" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  if ! grep -qE '^\[pi-shell-acp:cancel\] .*outcome=(dispatched|unsupported)' "$log_file"; then
    echo "[smoke-cancel/$backend] cancel outcome not in {dispatched, unsupported}" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  if ! grep -q '^\[pi-shell-acp:shutdown\]' "$log_file"; then
    echo "[smoke-cancel/$backend] missing [pi-shell-acp:shutdown] log line" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  if [[ "$rc" != "0" ]]; then
    echo "[smoke-cancel/$backend] node subprocess failed rc=$rc" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  local after
  after=$(pgrep -cf "$backend_pattern" 2>/dev/null) || after=0
  local delta=$((after - before))
  if [[ $delta -ne 0 ]]; then
    echo "[smoke-cancel/$backend] backend process delta=$delta (before=$before after=$after)" >&2
    pgrep -af "$backend_pattern" >&2 || true
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  echo "[smoke-cancel/$backend] ok (cancel logged, session reused, delta=0)"
  rm -f "$log_file"
}

smoke_cancel() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")

  require_cmd pi

  echo "[smoke-cancel] strict dual-backend cancel cleanup gate"
  echo "[smoke-cancel] project: $project_dir"
  echo "[smoke-cancel] repo:    $REPO_DIR"

  smoke_cancel_single "$project_dir" claude claude-sonnet-4-6
  smoke_cancel_single "$project_dir" codex gpt-5.2
  echo "[smoke-cancel] Claude + Codex cancel cleanup: ok"
}

smoke_model_switch_single() {
  local project_dir=$1
  local backend=$2
  local model_a=$3
  local model_b=$4

  echo "[smoke-model-switch/$backend] models: $model_a -> $model_b"

  local log_file
  log_file=$(mktemp /tmp/pi-shell-acp-model-switch-XXXXXX.log)

  local rc=0
  (
    cd "$REPO_DIR"
    PI_SHELL_ACP_SMOKE_BACKEND="$backend" \
    PI_SHELL_ACP_MODEL_A="$model_a" \
    PI_SHELL_ACP_MODEL_B="$model_b" \
      node --input-type=module 2>"$log_file" <<'EOF'
import {
  ensureBridgeSession,
  sendPrompt,
  setActivePromptHandler,
  closeBridgeSession,
  normalizeMcpServers,
} from './acp-bridge.ts';

const backend = process.env.PI_SHELL_ACP_SMOKE_BACKEND;
const modelA = process.env.PI_SHELL_ACP_MODEL_A;
const modelB = process.env.PI_SHELL_ACP_MODEL_B;
if (!backend || !modelA || !modelB) throw new Error('backend/modelA/modelB required');

const emptyMcpHash = normalizeMcpServers(undefined).hash;
const makeParams = (sessionKey, modelId) => ({
  sessionKey,
  cwd: process.cwd(),
  backend,
  modelId,
  systemPromptAppend: '간단히 답하세요.',
  settingSources: ['user'],
  strictMcpConfig: false,
  mcpServers: [],
  bridgeConfigSignature: JSON.stringify({
    backend,
    appendSystemPrompt: false,
    settingSources: ['user'],
    strictMcpConfig: false,
    mcpServersHash: emptyMcpHash,
  }),
  contextMessageSignatures: [`smoke-model-switch:${backend}`],
});

async function runOneTurn(session, label) {
  setActivePromptHandler(session, () => {});
  const result = await sendPrompt(session, [{ type: 'text', text: 'ok만 답하세요.' }]);
  setActivePromptHandler(session, undefined);
  if (result.stopReason !== 'end_turn') {
    throw new Error(`${label} turn stopReason=${result.stopReason}`);
  }
  console.error(`[smoke-model-switch] ${label} turn ok`);
}

// --- scenario 1: reuse applied ---
{
  const sessionKey = `smoke-ms-applied:${backend}`;
  const sessionA = await ensureBridgeSession(makeParams(sessionKey, modelA));
  await runOneTurn(sessionA, 'applied/turn1');
  // second call on same key with different modelId -> reuse branch
  await ensureBridgeSession(makeParams(sessionKey, modelB));
  await closeBridgeSession(sessionKey, { closeRemote: true, invalidatePersisted: true });
  console.error('[smoke-model-switch] applied scenario done');
}

// --- scenario 2: reuse unsupported -> new_session fallback ---
{
  const sessionKey = `smoke-ms-unsupported:${backend}`;
  const sessionA = await ensureBridgeSession(makeParams(sessionKey, modelA));
  await runOneTurn(sessionA, 'unsupported/turn1');
  // force unsupported by shadowing the prototype method with a non-function own property
  Object.defineProperty(sessionA.connection, 'unstable_setSessionModel', {
    value: undefined,
    configurable: true,
    writable: true,
  });
  const sessionB = await ensureBridgeSession(makeParams(sessionKey, modelB));
  if (sessionB === sessionA) {
    throw new Error('unsupported scenario: expected new session but got same reference');
  }
  await runOneTurn(sessionB, 'unsupported/turn2-post-fallback');
  await closeBridgeSession(sessionKey, { closeRemote: true, invalidatePersisted: true });
  console.error('[smoke-model-switch] unsupported scenario done');
}

// --- scenario 3: reuse failed -> new_session fallback ---
{
  const sessionKey = `smoke-ms-failed:${backend}`;
  const sessionA = await ensureBridgeSession(makeParams(sessionKey, modelA));
  await runOneTurn(sessionA, 'failed/turn1');
  sessionA.connection.unstable_setSessionModel = async () => {
    throw new Error('smoke-forced-setmodel-failure');
  };
  const sessionB = await ensureBridgeSession(makeParams(sessionKey, modelB));
  if (sessionB === sessionA) {
    throw new Error('failed scenario: expected new session but got same reference');
  }
  await runOneTurn(sessionB, 'failed/turn2-post-fallback');
  await closeBridgeSession(sessionKey, { closeRemote: true, invalidatePersisted: true });
  console.error('[smoke-model-switch] failed scenario done');
}

console.error('[smoke-model-switch] all scenarios ok');
EOF
  ) || rc=$?

  if [[ "$rc" != "0" ]]; then
    echo "[smoke-model-switch/$backend] node subprocess failed rc=$rc" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  # required reuse branches, all with matching backend
  local required=(
    "^\[pi-shell-acp:model-switch\] path=reuse outcome=applied .*backend=$backend .*toModel=$model_b"
    "^\[pi-shell-acp:model-switch\] path=reuse outcome=unsupported .*backend=$backend .*fallback=new_session"
    "^\[pi-shell-acp:model-switch\] path=reuse outcome=failed .*backend=$backend .*fallback=new_session .*reason=smoke-forced-setmodel-failure"
  )
  for pattern in "${required[@]}"; do
    if ! grep -qE "$pattern" "$log_file"; then
      echo "[smoke-model-switch/$backend] missing log matching: $pattern" >&2
      cat "$log_file" >&2
      rm -f "$log_file"
      exit 1
    fi
  done

  # fallback must produce a new bootstrap path=new after unsupported/failed
  local fallback_bootstraps
  fallback_bootstraps=$(grep -cE "^\[pi-shell-acp:bootstrap\] path=new backend=$backend" "$log_file" || true)
  if [[ "$fallback_bootstraps" -lt 4 ]]; then
    echo "[smoke-model-switch/$backend] expected >=4 bootstrap path=new lines, got $fallback_bootstraps" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  echo "[smoke-model-switch/$backend] ok (applied+unsupported+failed logged, fallbacks re-bootstrapped)"
  rm -f "$log_file"
}

smoke_model_switch() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")

  require_cmd pi

  echo "[smoke-model-switch] strict dual-backend model switch observability gate"
  echo "[smoke-model-switch] project: $project_dir"
  echo "[smoke-model-switch] repo:    $REPO_DIR"

  smoke_model_switch_single "$project_dir" claude claude-sonnet-4-6 claude-haiku-4-5-20251001
  smoke_model_switch_single "$project_dir" codex gpt-5.2 gpt-5.2-codex
  echo "[smoke-model-switch] Claude + Codex model switch observability: ok"
}

smoke_delegate_resume_single() {
  local project_dir=$1
  local backend=$2
  local model=$3
  local expected_path=$4
  local label=$5

  local session_file
  session_file=$(mktemp /tmp/pi-shell-acp-delegate-resume-XXXXXX.jsonl)

  echo "[smoke-delegate-resume/$backend] ${label}"
  echo "[smoke-delegate-resume/$backend] model=$model expected-turn2=$expected_path session=$session_file"

  local turn1_log turn1_rc=0
  turn1_log=$(cd "$project_dir" && PI_SHELL_ACP_STRICT_BOOTSTRAP=1 pi \
    --mode json -p --no-extensions \
    -e "$REPO_DIR" \
    --provider pi-shell-acp \
    --model "$model" \
    --session "$session_file" \
    'READY 만 답해' 2>&1) || turn1_rc=$?
  if [[ "$turn1_rc" != "0" ]]; then
    echo "[smoke-delegate-resume/$backend] turn1 pi invocation failed rc=$turn1_rc:" >&2
    echo "$turn1_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if ! grep -q "^\[pi-shell-acp:bootstrap\] path=new backend=$backend" <<< "$turn1_log"; then
    echo "[smoke-delegate-resume/$backend] turn1 expected path=new, got:" >&2
    echo "$turn1_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  local turn1_acp
  turn1_acp=$(grep -oE "^\[pi-shell-acp:bootstrap\] path=new backend=$backend [^$]*" <<< "$turn1_log" \
    | head -1 | grep -oE 'acpSessionId=[^ ]+' | head -1 | cut -d= -f2)
  if [[ -z "$turn1_acp" ]]; then
    echo "[smoke-delegate-resume/$backend] turn1 acpSessionId not extractable:" >&2
    echo "$turn1_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if ! grep -qE '"role":"assistant"' "$session_file"; then
    echo "[smoke-delegate-resume/$backend] turn1 session file has no assistant message" >&2
    cat "$session_file" >&2
    rm -f "$session_file"
    exit 1
  fi
  echo "[smoke-delegate-resume/$backend] turn1 path=new acpSessionId=$turn1_acp: ok"

  local turn2_log turn2_rc=0
  turn2_log=$(cd "$project_dir" && PI_SHELL_ACP_STRICT_BOOTSTRAP=1 pi \
    --mode json -p --no-extensions \
    -e "$REPO_DIR" \
    --provider pi-shell-acp \
    --model "$model" \
    --session "$session_file" \
    'OK 만 답해' 2>&1) || turn2_rc=$?
  if [[ "$turn2_rc" != "0" ]]; then
    echo "[smoke-delegate-resume/$backend] turn2 pi invocation failed rc=$turn2_rc:" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if ! grep -q "^\[pi-shell-acp:bootstrap\] path=$expected_path backend=$backend" <<< "$turn2_log"; then
    echo "[smoke-delegate-resume/$backend] turn2 expected path=$expected_path, got:" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  local turn2_acp
  turn2_acp=$(grep -oE "^\[pi-shell-acp:bootstrap\] path=$expected_path backend=$backend [^$]*" <<< "$turn2_log" \
    | head -1 | grep -oE 'acpSessionId=[^ ]+' | head -1 | cut -d= -f2)
  if [[ "$turn2_acp" != "$turn1_acp" ]]; then
    echo "[smoke-delegate-resume/$backend] acpSessionId mismatch turn1=$turn1_acp turn2=$turn2_acp" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if grep -q "^\[pi-shell-acp:bootstrap-invalidate\]" <<< "$turn2_log"; then
    echo "[smoke-delegate-resume/$backend] turn2 unexpected bootstrap-invalidate:" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if grep -q "^\[pi-shell-acp:bootstrap-fallback\]" <<< "$turn2_log"; then
    echo "[smoke-delegate-resume/$backend] turn2 unexpected bootstrap-fallback:" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi

  # assistant message from turn2 must land in the same session file
  local assistant_count
  assistant_count=$(grep -cE '"role":"assistant"' "$session_file" || true)
  if [[ "${assistant_count:-0}" -lt 2 ]]; then
    echo "[smoke-delegate-resume/$backend] expected >=2 assistant messages in session file, got ${assistant_count:-0}" >&2
    cat "$session_file" >&2
    rm -f "$session_file"
    exit 1
  fi
  # last assistant payload must be non-empty (guards against role-only or blank content records)
  local last_assistant_len
  last_assistant_len=$(SESSION_FILE="$session_file" node --input-type=module -e '
    import { readFileSync } from "node:fs";
    const lines = readFileSync(process.env.SESSION_FILE, "utf8").split("\n").filter(Boolean);
    let last = null;
    for (const raw of lines) {
      try {
        const rec = JSON.parse(raw);
        const msg = rec && rec.message ? rec.message : rec;
        if (msg && msg.role === "assistant") last = msg;
      } catch {}
    }
    if (!last) { console.log(0); process.exit(0); }
    const content = last.content;
    let len = 0;
    if (typeof content === "string") len = content.trim().length;
    else if (Array.isArray(content)) {
      for (const part of content) {
        if (typeof part === "string") len += part.trim().length;
        else if (part && typeof part.text === "string") len += part.text.trim().length;
      }
    } else if (content && typeof content.text === "string") len = content.text.trim().length;
    console.log(len);
  ' 2>/dev/null || echo 0)
  if [[ "${last_assistant_len:-0}" -lt 1 ]]; then
    echo "[smoke-delegate-resume/$backend] last assistant payload is empty (len=${last_assistant_len:-0})" >&2
    cat "$session_file" >&2
    rm -f "$session_file"
    exit 1
  fi
  echo "[smoke-delegate-resume/$backend] turn2 path=$expected_path acpSessionId=$turn2_acp (same as turn1, last-assistant-len=$last_assistant_len): ok"

  rm -f "$session_file"
}

smoke_compaction_single() {
  local project_dir=$1
  local backend=$2
  local model=$3

  local log_file token uuid
  log_file=$(mktemp /tmp/pi-shell-acp-compaction-XXXXXX.log)
  # Token is generated fresh per run so the check fails closed if Claude ever
  # has prior knowledge of the phrase (it won't — it's random per invocation).
  # Use bash builtins only — a `tr </dev/urandom | head -c` idiom tripped
  # SIGPIPE (rc=141) under `set -o pipefail`.
  uuid=$(</proc/sys/kernel/random/uuid)
  uuid=${uuid//-/}
  uuid=${uuid^^}
  token=${uuid:0:12}

  echo "[smoke-compaction/$backend] model=$model token=$token"

  local rc=0
  (
    cd "$REPO_DIR"
    PI_SHELL_ACP_SMOKE_BACKEND="$backend" \
    PI_SHELL_ACP_MODEL_ID="$model" \
    PI_SHELL_ACP_COMPACTION_TOKEN="$token" \
      node --input-type=module 2>"$log_file" <<'EOF'
import {
  ensureBridgeSession,
  sendPrompt,
  setActivePromptHandler,
  closeBridgeSession,
  normalizeMcpServers,
} from './acp-bridge.ts';
import { renderCompactionSystemPromptAppend } from './compaction-context.ts';

const backend = process.env.PI_SHELL_ACP_SMOKE_BACKEND;
const modelId = process.env.PI_SHELL_ACP_MODEL_ID;
const token = process.env.PI_SHELL_ACP_COMPACTION_TOKEN;
if (!backend || !modelId || !token) throw new Error('backend/model/token env required');

// Build a realistic post-compaction systemPromptAppend: summary contains the
// token, plus a couple of "kept" turns for shape. This is the string pi-shell-
// acp would synthesize from pi's compacted context.
const fakeCtx = {
  summary: `The operator shared a one-time session token that must be recalled verbatim when asked. The token is ${token}. Earlier we also discussed unrelated repo chores.`,
  keptMessages: [
    { role: 'user', content: 'Before I forget — please remember the token I just shared.' },
    {
      role: 'assistant',
      content: [{ type: 'text', text: 'Acknowledged. I have the token on file.' }],
      api: 'anthropic-messages', provider: 'anthropic', model: modelId,
      usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
      stopReason: 'stop', timestamp: 0,
    },
    { role: 'user', content: 'Thanks. Continue with the task plan when I ask.' },
    {
      role: 'assistant',
      content: [{ type: 'text', text: 'Understood.' }],
      api: 'anthropic-messages', provider: 'anthropic', model: modelId,
      usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
      stopReason: 'stop', timestamp: 0,
    },
  ],
  latestUserIndex: -1, // unused by renderer
};

const systemPromptAppend = renderCompactionSystemPromptAppend(fakeCtx);
const emptyMcpHash = normalizeMcpServers(undefined).hash;
const bridgeConfigSignature = JSON.stringify({
  backend, appendSystemPrompt: false, settingSources: ['user'],
  strictMcpConfig: false, mcpServersHash: emptyMcpHash,
});

const sessionKey = `smoke-compaction:${backend}:${modelId}`;
const baseParams = {
  sessionKey,
  cwd: process.cwd(),
  backend,
  modelId,
  systemPromptAppend,
  settingSources: ['user'],
  strictMcpConfig: false,
  mcpServers: [],
  bridgeConfigSignature,
  // Signatures mimic a real post-compaction context: one "user" for the summary
  // message, two kept exchanges, then the live turn.
  contextMessageSignatures: [
    'user:text:SUMMARY', 'user:text:kept-u1', 'assistant:text:kept-a1',
    'user:text:kept-u2', 'assistant:text:kept-a2', 'user:text:LATEST',
  ],
};

// --- Turn 21 (post-compaction): fresh Claude session, recall the token. ---
const sessionA = await ensureBridgeSession(baseParams);
const acpIdA = sessionA.acpSessionId;
console.error(`[smoke-compaction] turn1 acpSessionId=${acpIdA} bootstrapPath=${sessionA.bootstrapPath}`);
if (sessionA.bootstrapPath !== 'new') {
  throw new Error(`turn1 expected bootstrapPath=new, got ${sessionA.bootstrapPath}`);
}

let recalled = '';
setActivePromptHandler(sessionA, (event) => {
  if (event.type !== 'session_notification') return;
  const update = event.notification?.update;
  if (update?.sessionUpdate === 'agent_message_chunk' && update.content?.type === 'text') {
    recalled += update.content.text;
  }
});

const recallResult = await sendPrompt(sessionA, [{
  type: 'text',
  text: 'Please repeat the session token I shared earlier, exactly as it was given. Reply with only the token.',
}]);
setActivePromptHandler(sessionA, undefined);

if (recallResult.stopReason !== 'end_turn') {
  throw new Error(`turn1 stopReason=${recallResult.stopReason}`);
}
if (!recalled.includes(token)) {
  throw new Error(`turn1 response did not contain the token. token=${token} response=${JSON.stringify(recalled).slice(0, 300)}`);
}
console.error(`[smoke-compaction] turn1 token recall: ok (${token} present in response)`);

// --- Turn 22 (subsequent): same systemPromptAppend, signatures extended ---
// bootstrapPath must be "reuse" — the whole point of the deterministic
// renderer is so that Claude session A survives across post-compaction turns.
const turn2Params = {
  ...baseParams,
  contextMessageSignatures: [...baseParams.contextMessageSignatures, 'assistant:text:turn1-reply', 'user:text:NEW'],
};
const sessionB = await ensureBridgeSession(turn2Params);
if (sessionB !== sessionA) {
  throw new Error(`turn2 expected session reuse (same object), got a different session`);
}
if (sessionB.bootstrapPath !== 'reuse') {
  throw new Error(`turn2 expected bootstrapPath=reuse, got ${sessionB.bootstrapPath}`);
}
if (sessionB.acpSessionId !== acpIdA) {
  throw new Error(`turn2 acpSessionId drifted: ${acpIdA} -> ${sessionB.acpSessionId}`);
}
console.error(`[smoke-compaction] turn2 reuse preserved: ok (same acpSessionId=${acpIdA})`);

await closeBridgeSession(sessionKey, { closeRemote: true, invalidatePersisted: true });
console.error('[smoke-compaction] cleanup: ok');
EOF
  ) || rc=$?

  if [[ "$rc" != "0" ]]; then
    echo "[smoke-compaction/$backend] node subprocess failed rc=$rc" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  if ! grep -q '^\[smoke-compaction\] turn1 token recall: ok' "$log_file"; then
    echo "[smoke-compaction/$backend] token recall did not pass" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi
  if ! grep -q '^\[smoke-compaction\] turn2 reuse preserved: ok' "$log_file"; then
    echo "[smoke-compaction/$backend] reuse invariant did not hold" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  echo "[smoke-compaction/$backend] ok (token recalled + session reused across compaction-style turns)"
  rm -f "$log_file"
}

smoke_compaction() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")

  require_cmd pi

  echo "[smoke-compaction] post-compaction handoff live gate (Claude only — codex has no systemPromptAppend channel)"
  echo "[smoke-compaction] project: $project_dir"
  echo "[smoke-compaction] repo:    $REPO_DIR"

  smoke_compaction_single "$project_dir" claude claude-sonnet-4-6
  echo "[smoke-compaction] Claude compaction handoff: ok"
}

smoke_delegate_resume() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")

  require_cmd pi

  echo "[smoke-delegate-resume] bridge-level dual-backend continuity gate"
  echo "[smoke-delegate-resume] project: $project_dir"
  echo "[smoke-delegate-resume] repo:    $REPO_DIR"
  echo "[smoke-delegate-resume] scope:   bridge carries same-session turn1->turn2 via resume(Claude) / load(Codex)"
  echo "                       — spawn authority / target selection / parent×target matrix live in"
  echo "                         this repo's entwurf surface (pi/delegate-targets.json + mcp/pi-tools-bridge)."
  echo "                         This smoke validates BRIDGE carry only; orchestration is validated separately."

  smoke_delegate_resume_single "$project_dir" claude claude-sonnet-4-6 resume "bridge continuity (Claude → resumeSession)"
  smoke_delegate_resume_single "$project_dir" codex  gpt-5.2           load   "bridge continuity (Codex → loadSession)"

  echo "[smoke-delegate-resume] Claude(resume) + Codex(load) bridge continuity: ok"
}

check_mcp() {
  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import { normalizeMcpServers, McpServerConfigError } from './acp-bridge.ts';
import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';

const emptyHash = createHash('sha256').update('[]').digest('hex');

function expectThrow(label, fn) {
  try {
    fn();
  } catch (err) {
    if (!(err instanceof McpServerConfigError)) {
      throw new Error(`${label}: expected McpServerConfigError, got ${err?.name || err}`);
    }
    if (!Array.isArray(err.issues) || err.issues.length === 0) {
      throw new Error(`${label}: expected non-empty issues[]`);
    }
    for (const issue of err.issues) {
      if (typeof issue.server !== 'string' || issue.server.length === 0) {
        throw new Error(`${label}: issue missing server name`);
      }
    }
    return err;
  }
  throw new Error(`${label}: expected throw, got none`);
}

// 1. undefined -> empty, deterministic empty hash
{
  const r = normalizeMcpServers(undefined);
  assert.deepEqual(r.servers, [], '1.undefined: servers empty');
  assert.equal(r.hash, emptyHash, '1.undefined: hash matches sha256("[]")');
  assert.equal(r.signatureKey, '[]', '1.undefined: signatureKey is "[]"');
}

// 2. {} -> same empty shape
{
  const r = normalizeMcpServers({});
  assert.deepEqual(r.servers, []);
  assert.equal(r.hash, emptyHash);
}

// 3. canonical ordering: z before a in input -> a first in output
{
  const r = normalizeMcpServers({
    z: { command: 'bin-z' },
    a: { command: 'bin-a' },
  });
  assert.deepEqual(r.servers.map(s => s.name), ['a', 'z'], '3: sorted by name');
}

// 4. deterministic hash — same semantic input -> same hash
{
  const a = normalizeMcpServers({ x: { command: 'c', args: ['1', '2'], env: { B: '2', A: '1' } } });
  const b = normalizeMcpServers({ x: { command: 'c', args: ['1', '2'], env: { A: '1', B: '2' } } });
  assert.equal(a.hash, b.hash, '4: env key order must not change hash');
}

// 5. stdio default shape (no "type")
{
  const r = normalizeMcpServers({ s: { command: 'bin', args: ['--x'], env: { K: 'v' } } });
  assert.equal(r.servers.length, 1);
  const s = r.servers[0];
  assert.equal(s.name, 's');
  assert.equal(s.command, 'bin');
  assert.deepEqual(s.args, ['--x']);
  assert.deepEqual(s.env, [{ name: 'K', value: 'v' }]);
}

// 6. http shape
{
  const r = normalizeMcpServers({
    h: { type: 'http', url: 'https://e/mcp', headers: { Authorization: 'Bearer x' } },
  });
  const s = r.servers[0];
  assert.equal(s.type, 'http');
  assert.equal(s.url, 'https://e/mcp');
  assert.deepEqual(s.headers, [{ name: 'Authorization', value: 'Bearer x' }]);
}

// 7. sse shape
{
  const r = normalizeMcpServers({ e: { type: 'sse', url: 'https://e/sse' } });
  const s = r.servers[0];
  assert.equal(s.type, 'sse');
  assert.equal(s.url, 'https://e/sse');
}

// 8. unsupported type throws with server name
{
  const err = expectThrow('8.bad-type', () => normalizeMcpServers({ bad: { type: 'ws', url: 'x' } }));
  assert.equal(err.issues[0].server, 'bad');
  assert.match(err.message, /bad:/);
}

// 9. empty command throws
expectThrow('9.empty-command', () => normalizeMcpServers({ noop: { command: '' } }));

// 10. empty url (http) throws
expectThrow('10.empty-url-http', () => normalizeMcpServers({ u: { type: 'http', url: '' } }));

// 11. invalid env value throws
expectThrow('11.env-non-string', () => normalizeMcpServers({ e: { command: 'c', env: { K: 42 } } }));

// 12. args with non-string throws
expectThrow('12.args-non-string', () => normalizeMcpServers({ a: { command: 'c', args: ['ok', 5] } }));

// 13. root non-object (array) throws
expectThrow('13.root-array', () => normalizeMcpServers([]));

// 14. multiple invalid servers aggregated
{
  const err = expectThrow('14.aggregate', () => normalizeMcpServers({
    a: { command: '' },
    b: { type: 'ws' },
  }));
  assert.equal(err.issues.length, 2, '14: both issues surfaced');
  assert.deepEqual(err.issues.map(i => i.server).sort(), ['a', 'b']);
}

// 15. headers bad shape throws
expectThrow('15.headers-invalid', () => normalizeMcpServers({
  h: { type: 'http', url: 'https://x', headers: 'no' },
}));

console.log('[check-mcp] 15 assertions ok');
EOF
  )
}

check_backends() {
  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import { strict as assert } from 'node:assert';
import { buildSessionMetaForBackend, resolveAcpBackendLaunch } from './acp-bridge.ts';

const claudeOverride = 'node /tmp/fake-claude-acp.js';
const codexOverride = 'node /tmp/fake-codex-acp.js';
const prevClaude = process.env.CLAUDE_AGENT_ACP_COMMAND;
const prevCodex = process.env.CODEX_ACP_COMMAND;

process.env.CLAUDE_AGENT_ACP_COMMAND = claudeOverride;
process.env.CODEX_ACP_COMMAND = codexOverride;

try {
  const claudeLaunch = resolveAcpBackendLaunch('claude');
  assert.equal(claudeLaunch.command, 'bash');
  assert.deepEqual(claudeLaunch.args, ['-lc', claudeOverride]);
  assert.equal(claudeLaunch.source, 'env:CLAUDE_AGENT_ACP_COMMAND');

  const codexLaunch = resolveAcpBackendLaunch('codex');
  assert.equal(codexLaunch.command, 'bash');
  assert.deepEqual(codexLaunch.args, ['-lc', codexOverride]);
  assert.equal(codexLaunch.source, 'env:CODEX_ACP_COMMAND');

  const claudeMeta = buildSessionMetaForBackend('claude', {
    modelId: 'claude-sonnet-4-6',
    settingSources: ['user'],
    strictMcpConfig: true,
  }, 'system prompt');
  assert.equal(claudeMeta?.claudeCode?.options?.model, 'claude-sonnet-4-6');
  assert.deepEqual(claudeMeta?.claudeCode?.options?.settingSources, ['user']);
  assert.deepEqual(claudeMeta?.claudeCode?.options?.tools, { type: 'preset', preset: 'claude_code' });
  assert.deepEqual(claudeMeta?.systemPrompt, { append: 'system prompt' });
  assert.equal(claudeMeta?.claudeCode?.options?.extraArgs?.['strict-mcp-config'], null);

  const codexMeta = buildSessionMetaForBackend('codex', {
    modelId: 'codex-mini-latest',
    settingSources: ['user'],
    strictMcpConfig: true,
  }, 'system prompt');
  assert.equal(codexMeta, undefined);

  assert.throws(() => resolveAcpBackendLaunch(undefined), /ACP backend is required\./);
  assert.throws(() => resolveAcpBackendLaunch('bogus'), /Unknown ACP backend: bogus\./);

  console.log('[check-backends] 12 assertions ok');
} finally {
  if (prevClaude === undefined) delete process.env.CLAUDE_AGENT_ACP_COMMAND;
  else process.env.CLAUDE_AGENT_ACP_COMMAND = prevClaude;

  if (prevCodex === undefined) delete process.env.CODEX_ACP_COMMAND;
  else process.env.CODEX_ACP_COMMAND = prevCodex;
}
EOF
  )
}

check_models() {
  local verify_dir
  verify_dir="$REPO_DIR/.tmp-verify-models"

  rm -rf "$verify_dir"
  mkdir -p "$verify_dir"
  (
    cd "$REPO_DIR"
    ./node_modules/.bin/tsc \
      --project tsconfig.json \
      --outDir "$verify_dir" \
      --rootDir "$REPO_DIR"
  )

  # Run twice: once with default cap (200K), once with override (1M).
  # Each run imports a FRESH module URL so the top-level CLAUDE_CONTEXT_CAP
  # constant is recomputed from the env seen at import time.
  (cd "$REPO_DIR" && VERIFY_DIR="$verify_dir" node --input-type=module <<'EOF'
import { strict as assert } from 'node:assert';
import { pathToFileURL } from 'node:url';

const verifyDir = process.env.VERIFY_DIR;
if (!verifyDir) throw new Error('VERIFY_DIR is required');

// The model list is embedded in index.js by the registerProvider call.
// We capture it by mocking the runtime and letting the extension hand us
// `provider.models`. Override env before import to force a fresh read.

async function collectModels(envOverride) {
  if (envOverride === undefined) {
    delete process.env.PI_SHELL_ACP_CLAUDE_CONTEXT;
  } else {
    process.env.PI_SHELL_ACP_CLAUDE_CONTEXT = envOverride;
  }
  // Cache-bust: query string forces a fresh module evaluation so the
  // top-level `CLAUDE_CONTEXT_CAP` constant picks up the new env.
  const moduleUrl = pathToFileURL(`${verifyDir}/index.js`).href + `?cap=${envOverride ?? 'default'}`;
  const mod = await import(moduleUrl);
  let captured;
  const runtime = {
    registerProvider(_id, provider) { captured = provider; },
    on() {},
  };
  mod.default(runtime);
  if (!captured || !Array.isArray(captured.models)) {
    throw new Error('registerProvider did not receive a models array');
  }
  return new Map(captured.models.map((m) => [m.id, m]));
}

// --- Pass 1: curated surface + default cap (200K) ---
{
  const models = await collectModels(undefined);

  // Curated allowlist — exact match required. Adding or removing a model id
  // must flip this assertion, not silently drift.
  const EXPECTED_IDS = [
    'claude-sonnet-4-6',
    'claude-opus-4-7',
    'gpt-5.2',
    'gpt-5.4',
    'gpt-5.4-mini',
    'gpt-5.5',
  ].sort();
  const actualIds = [...models.keys()].sort();
  assert.deepEqual(
    actualIds, EXPECTED_IDS,
    `curated pi-shell-acp model surface mismatch.\n  expected: ${EXPECTED_IDS.join(', ')}\n  actual:   ${actualIds.join(', ')}`,
  );

  // Non-curated models MUST NOT leak through. Specifically: no legacy Claude
  // (3.x, 4.0-4.5, haiku), no generic openai chat models (gpt-4, gpt-4.1,
  // o1/o3/o4), no codex variants outside the allowlist (5.1, 5.3, codex-max).
  const FORBIDDEN = [
    'claude-3-5-sonnet-20241022', 'claude-3-5-haiku-latest',
    'claude-haiku-4-5', 'claude-sonnet-4-5', 'claude-opus-4-5',
    'claude-opus-4-6',
    'gpt-4', 'gpt-4-turbo', 'gpt-4.1', 'gpt-4.1-mini', 'gpt-4o',
    'o1', 'o3', 'o4-mini',
    'gpt-5', 'gpt-5-chat-latest',
    'gpt-5.1', 'gpt-5.1-codex-max', 'gpt-5.3-codex',
    'codex-mini-latest',
  ];
  for (const id of FORBIDDEN) {
    assert.ok(!models.has(id), `non-curated model ${id} must not be exposed by pi-shell-acp`);
  }

  // Claude 200K cap — the two curated 1M-capable models (sonnet-4-6, opus-4-7)
  // must be capped down without the env override.
  const oneMClaude = ['claude-sonnet-4-6', 'claude-opus-4-7'];
  for (const id of oneMClaude) {
    const m = models.get(id);
    assert.ok(m, `curated Claude model missing: ${id}`);
    assert.equal(
      m.contextWindow, 200000,
      `default: ${id} contextWindow should be capped at 200000, got ${m.contextWindow}`,
    );
  }

  // Codex context metadata — source is openai-codex (NOT openai). The regression
  // that motivated this gate: reading from openai source made pi-shell-acp
  // advertise gpt-5.5 ctx=1,050,000 while codex-acp could only serve 400,000.
  // Values below must match @mariozechner/pi-ai getModels("openai-codex") —
  // if upstream updates a context, update this gate with it.
  const CODEX_EXPECTED_CTX = {
    'gpt-5.2':      272000,
    'gpt-5.4':      272000,
    'gpt-5.4-mini': 272000,
    'gpt-5.5':      400000,
  };
  for (const [id, expected] of Object.entries(CODEX_EXPECTED_CTX)) {
    const m = models.get(id);
    assert.ok(m, `curated Codex model missing: ${id}`);
    assert.equal(
      m.contextWindow, expected,
      `${id} contextWindow must come from openai-codex source: expected ${expected}, got ${m.contextWindow}`,
    );
  }

  // Explicit anti-bug: gpt-5.5 must not be 1,050,000. The openai source claims
  // that for Chat Completions, but codex-acp can't serve it.
  assert.notEqual(
    models.get('gpt-5.5')?.contextWindow, 1050000,
    'gpt-5.5 at 1,050,000 context = openai source bug (should be openai-codex 400,000)',
  );

  console.log('[check-models] pass 1 (curated surface + default 200K cap + codex source): ok');
}

// --- Pass 2: explicit 1M opt-in ---
{
  const models = await collectModels('1000000');
  const id = 'claude-sonnet-4-6';
  const m = models.get(id);
  if (m) {
    assert.equal(
      m.contextWindow,
      1_000_000,
      `override: ${id} contextWindow should be 1000000 with PI_SHELL_ACP_CLAUDE_CONTEXT=1000000, got ${m.contextWindow}`,
    );
    console.log('[check-models] pass 2 (PI_SHELL_ACP_CLAUDE_CONTEXT=1000000 opt-in): ok');
  } else {
    console.log('[check-models] pass 2 skipped (claude-sonnet-4-6 not in registry)');
  }
}

// --- Pass 3: bogus override falls back to default ---
{
  const models = await collectModels('not-a-number');
  const id = 'claude-sonnet-4-6';
  const m = models.get(id);
  if (m) {
    assert.equal(
      m.contextWindow,
      200000,
      `bogus override: ${id} should fall back to 200000, got ${m.contextWindow}`,
    );
    console.log('[check-models] pass 3 (bogus override falls back): ok');
  }
}

delete process.env.PI_SHELL_ACP_CLAUDE_CONTEXT;
console.log('[check-models] all passes ok');
EOF
  )

  rm -rf "$verify_dir"
}

check_compaction_handoff() {
  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import { strict as assert } from 'node:assert';
import {
  detectCompactionContext,
  renderCompactionSystemPromptAppend,
  COMPACTION_PREFIX_LITERAL,
  COMPACTION_SUFFIX_LITERAL,
} from './compaction-context.ts';

function makeMessage(role, content) {
  const base = { role, content, timestamp: 0 };
  if (role === 'assistant') {
    return { ...base, api: 'anthropic-messages', provider: 'anthropic', model: 'test', usage: {
      input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
    }, stopReason: 'stop' };
  }
  return base;
}

const fakeSummary = 'This is the synthetic summary of turns 1 through 17.';
const summaryText = `${COMPACTION_PREFIX_LITERAL}${fakeSummary}${COMPACTION_SUFFIX_LITERAL}`;

// --- Case 1: no compaction — normal context ---
{
  const ctx = {
    systemPrompt: 'sys',
    messages: [
      makeMessage('user', 'hello'),
      makeMessage('assistant', [{ type: 'text', text: 'hi' }]),
      makeMessage('user', 'what time is it?'),
    ],
  };
  const result = detectCompactionContext(ctx);
  assert.equal(result, null, 'non-compaction context should return null');
  console.log('[check-compaction-handoff] case 1 (no compaction): ok');
}

// --- Case 2: typical post-compaction context ---
{
  const keptUser18 = makeMessage('user', 'msg18');
  const keptAsst18 = makeMessage('assistant', [{ type: 'text', text: 'asst18 body' }]);
  const keptUser19 = makeMessage('user', 'msg19');
  const keptAsst19 = makeMessage('assistant', [{ type: 'text', text: 'asst19 body' }]);
  const keptUser20 = makeMessage('user', 'msg20');
  const keptAsst20 = makeMessage('assistant', [{ type: 'text', text: 'asst20 body' }]);
  const newUser21 = makeMessage('user', 'msg21');

  const ctx = {
    systemPrompt: 'sys',
    messages: [
      makeMessage('user', summaryText),
      keptUser18, keptAsst18,
      keptUser19, keptAsst19,
      keptUser20, keptAsst20,
      newUser21,
    ],
  };
  const result = detectCompactionContext(ctx);
  assert.ok(result, 'compaction should be detected');
  assert.equal(result.summary, fakeSummary, 'summary body should be recovered verbatim');
  assert.equal(result.keptMessages.length, 6, 'kept window should be 6 messages (msg18..asst20)');
  assert.equal(result.latestUserIndex, 7, 'latest user index should point at msg21');

  const rendered = renderCompactionSystemPromptAppend(result);
  assert.ok(rendered.includes(fakeSummary), 'rendered append must contain the raw summary text');
  assert.ok(rendered.includes('asst18 body'), 'rendered append must include kept assistant text');
  assert.ok(rendered.includes('User: msg20'), 'rendered append must include kept user text with role label');
  // Most important invariant: latest turn must NOT be in the append (it stays in extractPromptBlocks).
  assert.ok(!rendered.includes('msg21'), 'rendered append must NOT include the latest user turn');
  console.log('[check-compaction-handoff] case 2 (typical compaction): ok');
}

// --- Case 3: determinism — same input must produce identical append ---
{
  const build = (latest) => ({
    systemPrompt: '',
    messages: [
      makeMessage('user', summaryText),
      makeMessage('user', 'kept-u'),
      makeMessage('assistant', [{ type: 'text', text: 'kept-a' }]),
      makeMessage('user', latest),
    ],
  });
  const a = renderCompactionSystemPromptAppend(detectCompactionContext(build('first'))); // latest = 'first'
  const b = renderCompactionSystemPromptAppend(detectCompactionContext(build('second'))); // latest differs
  assert.equal(a, b, 'append must be stable regardless of the latest user turn text (drives reuse)');
  // And a second call with the exact same object yields the same string.
  const c = renderCompactionSystemPromptAppend(detectCompactionContext(build('first')));
  assert.equal(a, c, 'append is pure — same input yields same output');
  console.log('[check-compaction-handoff] case 3 (determinism): ok');
}

// --- Case 4: summary-only context (no kept turns, just summary + latest user) ---
{
  const ctx = {
    systemPrompt: '',
    messages: [
      makeMessage('user', summaryText),
      makeMessage('user', 'brand new question'),
    ],
  };
  const result = detectCompactionContext(ctx);
  assert.ok(result, 'should detect compaction');
  assert.equal(result.keptMessages.length, 0, 'no kept turns');
  assert.equal(result.latestUserIndex, 1, 'latest user at index 1');
  const rendered = renderCompactionSystemPromptAppend(result);
  assert.ok(rendered.includes(fakeSummary));
  assert.ok(!rendered.includes('Recent exchanges preserved'), 'should skip the "recent exchanges" section when keptMessages is empty');
  console.log('[check-compaction-handoff] case 4 (summary-only): ok');
}

// --- Case 5: content-blocks form (array, not string) for the summary message ---
{
  const ctx = {
    systemPrompt: '',
    messages: [
      makeMessage('user', [{ type: 'text', text: summaryText }]),
      makeMessage('user', 'x'),
    ],
  };
  const result = detectCompactionContext(ctx);
  assert.ok(result, 'must detect compaction even when content is a text-block array');
  assert.equal(result.summary, fakeSummary);
  console.log('[check-compaction-handoff] case 5 (text-block array form): ok');
}

// --- Case 6: false positive guard — user message whose body merely mentions the prefix words ---
{
  const ctx = {
    systemPrompt: '',
    messages: [
      makeMessage('user', 'Hey, could you compact the logs into a summary?'),
      makeMessage('user', 'nope'),
    ],
  };
  const result = detectCompactionContext(ctx);
  assert.equal(result, null, 'must not mistake casual text for the compaction wrapper');
  console.log('[check-compaction-handoff] case 6 (false-positive guard): ok');
}

// --- Case 7: first message is assistant (never valid for pi, but guard) ---
{
  const ctx = {
    systemPrompt: '',
    messages: [
      makeMessage('assistant', [{ type: 'text', text: summaryText }]),
      makeMessage('user', 'x'),
    ],
  };
  const result = detectCompactionContext(ctx);
  assert.equal(result, null, 'first non-user message must not trigger detection');
  console.log('[check-compaction-handoff] case 7 (non-user first message): ok');
}

console.log('[check-compaction-handoff] all 7 cases ok');
EOF
  )
}

check_registration() {
  local verify_dir
  verify_dir="$REPO_DIR/.tmp-verify"

  mkdir -p "$verify_dir"
  (
    cd "$REPO_DIR"
    ./node_modules/.bin/tsc \
      --project tsconfig.json \
      --outDir "$verify_dir" \
      --rootDir "$REPO_DIR"
  )

  (cd "$REPO_DIR" && VERIFY_DIR="$verify_dir" node --input-type=module <<'EOF'
import { strict as assert } from 'node:assert';
import { pathToFileURL } from 'node:url';

const verifyDir = process.env.VERIFY_DIR;
if (!verifyDir) {
  throw new Error('VERIFY_DIR is required');
}

const moduleUrl = pathToFileURL(`${verifyDir}/index.js`).href;
const { default: registerProviderExtension } = await import(moduleUrl);

const providerCalls = [];
const eventCalls = [];

function makeRuntime(label) {
  return {
    registerProvider(providerId, provider) {
      providerCalls.push({ label, providerId, provider });
    },
    on(event, handler) {
      eventCalls.push({ label, event, handlerType: typeof handler });
    },
  };
}

const runtimeA = makeRuntime('runtime-a');
const runtimeB = makeRuntime('runtime-b');

registerProviderExtension(runtimeA);
registerProviderExtension(runtimeA);
registerProviderExtension(runtimeB);

assert.equal(providerCalls.length, 2, 'registerProvider should run once per runtime');
assert.deepEqual(providerCalls.map((call) => call.label), ['runtime-a', 'runtime-b']);
assert.deepEqual(providerCalls.map((call) => call.providerId), ['pi-shell-acp', 'pi-shell-acp']);
assert.ok(providerCalls.every((call) => Array.isArray(call.provider.models) && call.provider.models.length > 0), 'models must be registered');

assert.equal(eventCalls.length, 2, 'session shutdown handler should be attached once per runtime');
assert.deepEqual(eventCalls.map((call) => `${call.label}:${call.event}`), [
  'runtime-a:session_shutdown',
  'runtime-b:session_shutdown',
]);
assert.ok(eventCalls.every((call) => call.handlerType === 'function'), 'session shutdown handlers must be functions');

console.log('[check-registration] 7 assertions ok');
EOF
  )
}

check_claude_sessions() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")

  (cd "$REPO_DIR" && PROJECT_DIR="$project_dir" node --input-type=module <<'EOF'
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { listSessions } from './node_modules/@agentclientprotocol/claude-agent-acp/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs';

const projectDir = process.env.PROJECT_DIR;
if (!projectDir) {
  throw new Error('PROJECT_DIR is required');
}

const cacheDir = join(homedir(), '.pi', 'agent', 'cache', 'pi-shell-acp', 'sessions');
const visibleSessions = await listSessions({ dir: projectDir, limit: 100 });
const visibleById = new Map(visibleSessions.map((session) => [session.sessionId, session]));

const persisted = [];
if (existsSync(cacheDir)) {
  for (const entry of readdirSync(cacheDir)) {
    if (!entry.endsWith('.json')) continue;
    const filePath = join(cacheDir, entry);
    try {
      const record = JSON.parse(readFileSync(filePath, 'utf8'));
      if (record?.provider !== 'pi-shell-acp') continue;
      if (record?.cwd !== projectDir) continue;
      if (typeof record?.acpSessionId !== 'string' || typeof record?.sessionKey !== 'string') continue;
      persisted.push(record);
    } catch {
      // ignore malformed cache entries
    }
  }
}

persisted.sort((a, b) => Date.parse(b.updatedAt ?? 0) - Date.parse(a.updatedAt ?? 0));

console.log(`[check-claude-sessions] project=${projectDir}`);
console.log(`[check-claude-sessions] cacheDir=${cacheDir}`);
console.log(`[check-claude-sessions] claudeVisible=${visibleSessions.length} persistedMatches=${persisted.length}`);

for (const record of persisted.slice(0, 12)) {
  const visible = visibleById.get(record.acpSessionId);
  const marker = visible ? 'VISIBLE' : 'MISSING';
  const summary = visible?.summary ? ` summary=${JSON.stringify(visible.summary)}` : '';
  console.log(`${marker} acp=${record.acpSessionId} sessionKey=${record.sessionKey} updated=${record.updatedAt}${summary}`);
}
EOF
  )
}

verify_resume() {
  local project_dir session_file model prompt_a prompt_b
  project_dir=$(normalize_project_dir "$1")
  model=${PI_SHELL_ACP_VERIFY_MODEL:-claude-3-5-haiku-latest}
  prompt_a=${PI_SHELL_ACP_VERIFY_PROMPT_A:-'Remember this exact secret token for later: test-token-123. Reply only READY.'}
  prompt_b=${PI_SHELL_ACP_VERIFY_PROMPT_B:-'What was the secret token? Reply with the token only.'}
  session_file=$(mktemp /tmp/pi-shell-acp-verify-XXXXXX.jsonl)

  require_cmd pi

  echo "[verify-resume] project:      $project_dir"
  echo "[verify-resume] repo:         $REPO_DIR"
  echo "[verify-resume] model:        $model"
  echo "[verify-resume] session-file: $session_file"
  echo "[verify-resume] turn1: pi should log bootstrap=new and an acpSessionId"
  (
    cd "$project_dir"
    PI_SHELL_ACP_DEBUG=1 pi -e "$REPO_DIR" --session "$session_file" --provider pi-shell-acp --model "$model" -p "$prompt_a"
  )
  echo "[verify-resume] turn2: pi should log bootstrap=resume or bootstrap=load with the same acpSessionId"
  (
    cd "$project_dir"
    PI_SHELL_ACP_DEBUG=1 pi -e "$REPO_DIR" --session "$session_file" --provider pi-shell-acp --model "$model" -p "$prompt_b"
  )
  check_claude_sessions "$project_dir"
}

CLAUDE_ACP_REQUIRED_VERSION="0.30.0"
CODEX_ACP_REQUIRED_VERSION="0.11.1"

check_global_claude_acp() {
  local installed
  installed=$(pnpm list -g --depth=0 2>/dev/null | grep -oE '@agentclientprotocol/claude-agent-acp@[0-9.]+' | grep -oE '[0-9.]+$' || true)
  if [[ "$installed" == "$CLAUDE_ACP_REQUIRED_VERSION" ]]; then
    echo "[setup] claude-agent-acp global: $installed (ok)"
  elif [[ -n "$installed" ]]; then
    echo "[setup] warning: claude-agent-acp global is $installed, expected $CLAUDE_ACP_REQUIRED_VERSION" >&2
    echo "[setup] run: pnpm add -g @agentclientprotocol/claude-agent-acp@$CLAUDE_ACP_REQUIRED_VERSION" >&2
  else
    echo "[setup] warning: claude-agent-acp not found in pnpm global" >&2
    echo "[setup] run: pnpm add -g @agentclientprotocol/claude-agent-acp@$CLAUDE_ACP_REQUIRED_VERSION" >&2
  fi
}

check_global_codex_acp() {
  local installed
  installed=$(pnpm list -g --depth=0 2>/dev/null | grep -oE '@zed-industries/codex-acp@[0-9.]+' | grep -oE '[0-9.]+$' || true)
  if [[ "$installed" == "$CODEX_ACP_REQUIRED_VERSION" ]]; then
    echo "[setup] codex-acp global: $installed (ok)"
  elif [[ -n "$installed" ]]; then
    echo "[setup] warning: codex-acp global is $installed, expected $CODEX_ACP_REQUIRED_VERSION" >&2
    echo "[setup] run: pnpm add -g @zed-industries/codex-acp@$CODEX_ACP_REQUIRED_VERSION" >&2
  else
    echo "[setup] warning: codex-acp not found in pnpm global" >&2
    echo "[setup] run: pnpm add -g @zed-industries/codex-acp@$CODEX_ACP_REQUIRED_VERSION" >&2
  fi
}

# --- Axis 1 interview-prerequisite gates (ported from agent-config pre-Phase-4) ---
#
# These three validators complement the local deterministic check_* gates by
# actually exercising the runtime surfaces the agent interview depends on:
#
#   1. pi-tools-bridge as a standalone MCP server (tools/list + protocol suite)
#   2. pi-tools-bridge visibility + callability from inside a pi-shell-acp
#      ACP session, for both backends (claude + codex)
#   3. pi-native async delegate spawn via `pi -e pi-extensions/delegate.ts`
#
# AGENTS.md §Ingestion Gates (Axis 1) names these as required gates that must
# pass before the Axis 2 agent interview can be re-run. They were implemented
# in agent-config and deleted there in Phase 4 alongside the migrated code;
# their canonical home is now this repo.

pi_tools_bridge_require_tools() {
  local raw="$1"
  local backend_label="$2"
  local tool

  if [[ "$raw" == *"NOT_VISIBLE"* ]]; then
    echo "$raw" >&2
    fail "pi-tools-bridge: $backend_label returned NOT_VISIBLE"
    return 1
  fi

  if [[ "$raw" != *"pi-tools-bridge"* ]] && [[ "$raw" != *"pi_tools_bridge"* ]]; then
    echo "$raw" >&2
    fail "pi-tools-bridge: $backend_label visibility output missing pi-tools-bridge prefix"
    return 1
  fi

  for tool in session_search knowledge_search send_to_session list_sessions delegate delegate_resume; do
    if [[ "$raw" != *"$tool"* ]]; then
      echo "$raw" >&2
      fail "pi-tools-bridge: $backend_label missing tool $tool"
      return 1
    fi
  done

  return 0
}

validate_pi_tools_bridge_backend() {
  local backend_label="$1"
  local model="$2"
  local raw

  if ! raw=$(cd "$REPO_DIR" && pi -e "$REPO_DIR" --provider pi-shell-acp --model "$model" -p '지금 이 세션에서 보이는 MCP 도구 중 이름에 pi-tools-bridge 또는 pi_tools_bridge 가 포함된 도구가 있으면 정확한 도구 이름만 쉼표로 나열해. 설명 금지. 없으면 정확히 NOT_VISIBLE 만 답해.'); then
    fail "pi-tools-bridge: $backend_label visibility smoke failed"
    return 1
  fi
  pi_tools_bridge_require_tools "$raw" "$backend_label" || return 1
  ok "pi-tools-bridge visibility via pi-shell-acp ($backend_label: $raw)"

  if ! raw=$(cd "$REPO_DIR" && pi -e "$REPO_DIR" --provider pi-shell-acp --model "$model" -p 'send_to_session 도구가 보이면 반드시 그 도구를 실제로 1회 호출해. target은 __definitely_does_not_exist__, message는 "ping", mode는 follow_up 으로 해. functions.send_input 같은 다른 도구는 절대 쓰지 마. 응답은 두 줄만: 1) TOOL:<사용한 도구명 또는 NONE> 2) RESULT:<성공/실패 핵심 메시지 한 줄>. 도구가 안 보이면 TOOL:NONE / RESULT:not visible 로만 답해.' ); then
    fail "pi-tools-bridge: $backend_label invocation smoke failed"
    return 1
  fi

  if [[ "$raw" != *"send_to_session"* ]]; then
    echo "$raw" >&2
    fail "pi-tools-bridge: $backend_label invocation did not use send_to_session"
    return 1
  fi

  if [[ "$raw" != *"[tool:failed]"* ]] && [[ "$raw" != *"RESULT:실패"* ]] && [[ "$raw" != *"RESULT:failure"* ]]; then
    echo "$raw" >&2
    fail "pi-tools-bridge: $backend_label invocation did not clearly surface a failure result"
    return 1
  fi

  # Robustness: the model paraphrases the tool error in many ways. The most
  # reliable anchor is the bogus target name itself — if it appears in the
  # response, the model engaged with the actual tool result. Phrase patterns
  # are kept as fallbacks for older outputs / different model behavior.
  if [[ "$raw" != *"__definitely_does_not_exist__"* ]] && \
     [[ "$raw" != *"No pi control socket"* ]] && \
     [[ "$raw" != *"control socket"* ]] && \
     [[ "$raw" != *"컨트롤 소켓"* ]] && \
     [[ "$raw" != *"대상 세션"* ]] && \
     [[ "$raw" != *"미존재"* ]] && \
     [[ "$raw" != *"존재하지"* ]] && \
     [[ "$raw" != *"소켓"* ]] && \
     [[ "$raw" != *"not found"* ]] && \
     [[ "$raw" != *"no such"* ]]; then
    echo "$raw" >&2
    fail "pi-tools-bridge: $backend_label invocation did not surface the expected missing-target boundary"
    return 1
  fi
  ok "pi-tools-bridge invocation via pi-shell-acp ($backend_label)"
}

validate_pi_tools_bridge() {
  local bridge_dir="$REPO_DIR/mcp/pi-tools-bridge"
  local raw

  if [ ! -f "$bridge_dir/package.json" ]; then
    fail "pi-tools-bridge: repo content missing at $bridge_dir"
    return 1
  fi

  log "pi-tools-bridge: install + build + validate..."

  if ! (cd "$bridge_dir" && pnpm install --silent); then
    fail "pi-tools-bridge: pnpm install failed"
    return 1
  fi
  ok "pi-tools-bridge pnpm install"

  if ! (cd "$bridge_dir" && pnpm run build); then
    fail "pi-tools-bridge: build failed"
    return 1
  fi
  ok "pi-tools-bridge build"

  if ! raw=$(cd "$bridge_dir" && node --input-type=module <<'JS'
import { spawn } from 'node:child_process';

const child = spawn('./start.sh');
let stdout = '';
let stderr = '';
let done = false;

function finishOk(trimmed) {
  if (done) return;
  done = true;
  clearTimeout(timer);
  if (stderr.trim()) console.error(stderr.trim());
  const msg = JSON.parse(trimmed);
  const tools = msg?.result?.tools;
  if (!Array.isArray(tools)) {
    console.error('tools/list response missing result.tools');
    process.exit(1);
  }
  const names = tools.map((t) => t?.name).sort();
  const expected = ['delegate', 'delegate_resume', 'knowledge_search', 'list_sessions', 'send_to_session', 'session_search'];
  for (const name of expected) {
    if (!names.includes(name)) {
      console.error(`missing MCP tool: ${name}`);
      process.exit(1);
    }
  }
  console.log(names.join(','));
  child.kill('SIGTERM');
  process.exit(0);
}

child.stdout.on('data', (d) => {
  stdout += d.toString();
  const trimmed = stdout.trim();
  if (trimmed) finishOk(trimmed);
});
child.stderr.on('data', (d) => { stderr += d.toString(); });
child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }) + '\n');

const timer = setTimeout(() => {
  child.kill('SIGKILL');
  console.error('pi-tools-bridge direct smoke timeout');
  process.exit(1);
}, 3000);

child.on('error', (err) => {
  if (done) return;
  clearTimeout(timer);
  console.error(String(err));
  process.exit(1);
});

child.on('close', () => {
  if (done) return;
  clearTimeout(timer);
  const trimmed = stdout.trim();
  if (!trimmed) {
    if (stderr.trim()) console.error(stderr.trim());
    console.error('empty tools/list response');
    process.exit(1);
  }
  finishOk(trimmed);
});
JS
  ); then
    fail "pi-tools-bridge: direct MCP smoke failed"
    return 1
  fi
  ok "pi-tools-bridge direct MCP smoke ($raw)"

  if ! (cd "$bridge_dir" && ./test.sh >/dev/null); then
    fail "pi-tools-bridge: protocol/negative-path tests failed"
    return 1
  fi
  ok "pi-tools-bridge test.sh"

  # Qualified model ids here: the validation routes through pi-shell-acp explicitly.
  # The prefix stays redundant with the function's internal `--provider pi-shell-acp`
  # pin, but it documents intent at the call site.
  validate_pi_tools_bridge_backend "claude" "pi-shell-acp/claude-sonnet-4-6" || return 1
  validate_pi_tools_bridge_backend "codex" "pi-shell-acp/gpt-5.2" || return 1
}

# pi-native async delegate spawn smoke. Loads the native delegate.ts directly
# and asks a cheap model to invoke `delegate` in async mode against a bogus
# host. We read pi's --mode json event stream so the gate inspects the tool's
# *actual* sync return (which contains "Async delegate spawned" + Task ID),
# not the model's natural-language interpretation. We also grep explicitly for
# the regression class PM flagged: a stale `explicitExtensions` reference in
# runDelegateAsync would surface as a ReferenceError in the tool result.
validate_pi_native_async_delegate() {
  local raw
  log "pi-native: async delegate spawn smoke (model: gpt-5.4-mini)..."

  if ! raw=$(cd "$REPO_DIR" && pi -p \
              --mode json \
              --no-extensions \
              -e "$REPO_DIR/pi-extensions/delegate.ts" \
              --provider openai-codex \
              --model gpt-5.4-mini \
              'delegate 도구를 task="noop", host="__native_async_smoke_bogus__", mode="async" 인수로 정확히 1회 호출하라. 도구의 첫 sync 응답을 그대로 echo하라. 그 다음에 도착하는 follow-up 메시지는 무시하고 더 출력하지 마라.' 2>&1); then
    echo "$raw" >&2
    fail "pi-native async delegate smoke: pi -p exited non-zero"
    return 1
  fi

  # Regression class PM flagged: stale variable name in runDelegateAsync.
  #
  # NOTE on here-strings: $raw can exceed 800KB (pi --mode json is chatty),
  # and `set -o pipefail` is active. The pattern `echo "$raw" | grep -q ...`
  # races — grep -q exits 0 on first match, echo then gets SIGPIPE (rc=141),
  # and pipefail elevates the whole pipe's rc to 141 → `if` sees "fail" even
  # though the match happened. Observed in setup runs where raw > ~500KB.
  # Here-strings (`<<< "$raw"`) feed stdin without a pipeline, sidestepping
  # pipefail entirely. Keep this form for any grep check on large $raw.
  if grep -qE 'ReferenceError.*explicitExtensions|explicitExtensions is not defined' <<< "$raw"; then
    echo "$raw" >&2
    fail "pi-native async: ReferenceError on 'explicitExtensions' (stale variable resurfaced)"
    return 1
  fi

  # The sync tool return contains these strings verbatim — independent of how
  # the model paraphrases. Either marker proves the spawn completed cleanly.
  if grep -qE 'Async delegate spawned|Task ID:' <<< "$raw"; then
    local taskid
    # `head -1` still closes its stdin early, which can send SIGPIPE back
    # to grep under pipefail. Swallow the rc so the assignment survives —
    # the captured string is the only thing we need.
    taskid=$(grep -oE 'Task ID: [a-f0-9]+' <<< "$raw" | head -1 || true)
    ok "pi-native async delegate spawn (${taskid:-Task ID present})"
    return 0
  fi

  echo "$raw" >&2
  fail "pi-native async delegate produced neither Task ID nor a recognized error"
  return 1
}

check_bridge() {
  section "pi-tools-bridge (direct MCP + backend visibility)"
  validate_pi_tools_bridge
}

check_native_async() {
  section "pi-native async delegate spawn"
  validate_pi_native_async_delegate
}

sentinel_run() {
  local sentinel="$REPO_DIR/scripts/sentinel-runner.sh"
  if [ ! -x "$sentinel" ]; then
    fail "sentinel: $sentinel not found or not executable"
    return 1
  fi
  "$sentinel" "$@"
}

session_messaging_run() {
  local smoke="$REPO_DIR/scripts/session-messaging-smoke.sh"
  if [ ! -x "$smoke" ]; then
    fail "session-messaging: $smoke not found or not executable"
    return 1
  fi
  "$smoke" "$@"
}

# setup_all — full pi-shell-acp install.
#
# Installs the bridge + entwurf orchestration surface (delegate registry,
# MCP pi-tools-bridge, session-bridge) into a target project and verifies
# end-to-end against both ACP backends. As of the entwurf migration this
# repo owns the orchestration — there is no separate "consuming harness"
# install for the delegate/registry pieces.
#
# An external harness that consumes pi-shell-acp (e.g. agent-config as a
# pi package + skills set) may still have its own install/setup for its
# own concerns; those are outside the scope of this script.
setup_all() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")

  require_cmd pnpm
  require_cmd python3
  require_cmd pi

  echo "[setup] repo:    $REPO_DIR"
  echo "[setup] project: $project_dir"
  echo "[setup] scope:   full bridge + entwurf orchestration install"
  echo "[setup] verification: smoke-all + Axis 1 interview gates (pi-tools-bridge, pi-native async, sentinel, session-messaging)"

  (cd "$REPO_DIR" && pnpm install)
  check_global_claude_acp
  check_global_codex_acp
  sync_auth
  install_local_package "$project_dir"

  if [[ -f "$HOME/.claude.json" ]]; then
    echo "[setup] ~/.claude.json detected"
  else
    echo "[setup] warning: ~/.claude.json not found. Run 'npx @anthropic-ai/claude-code' first if needed." >&2
  fi

  # Deterministic preflight — cheap local gates run before any ACP/Claude
  # subprocess. Catches static-contract regressions (MCP shape, backend launch,
  # provider registration, model contextWindow cap) without waiting for smoke.
  echo "[setup] preflight: local deterministic checks"
  check_mcp
  check_backends
  check_registration
  check_models
  check_compaction_handoff

  smoke_all "$project_dir"

  # Axis 1 interview-prerequisite gates. AGENTS.md §Ingestion Gates names
  # these as required before the Axis 2 agent interview can be re-run.
  # Ported from agent-config pre-Phase-4 (validator bodies) + 7545af8
  # (session-messaging matrix) + pre-Phase-4 sentinel invocation. Default ON
  # here; agent-config (consumer) does not run these anymore.
  section "Axis 1 gate: pi-tools-bridge (direct MCP + backend visibility)"
  validate_pi_tools_bridge

  section "Axis 1 gate: pi-native async delegate spawn"
  validate_pi_native_async_delegate

  section "Axis 1 gate: session-messaging 4-case matrix"
  session_messaging_run

  section "Axis 1 gate: sentinel (delegate 6-cell matrix)"
  if sentinel_run; then
    ok "sentinel 6/6 PASS"
  else
    fail "sentinel: one or more cells failed — see table above and artifact"
    echo ""
    echo "DONE: pi-shell-acp setup complete (with sentinel failures)"
    return 1
  fi

  echo ""
  echo "DONE: pi-shell-acp setup + Axis 1 gates green. Axis 2 interview may proceed."
}

cmd=${1:-}
case "$cmd" in
  setup)
    setup_all "$TARGET_PROJECT_DIR"
    ;;
  smoke)
    smoke_test "$TARGET_PROJECT_DIR" claude
    ;;
  smoke-claude)
    smoke_test "$TARGET_PROJECT_DIR" claude
    ;;
  smoke-codex)
    smoke_test "$TARGET_PROJECT_DIR" codex
    ;;
  smoke-all)
    smoke_all "$TARGET_PROJECT_DIR"
    ;;
  smoke-continuity)
    smoke_continuity "$TARGET_PROJECT_DIR"
    ;;
  smoke-cancel)
    smoke_cancel "$TARGET_PROJECT_DIR"
    ;;
  smoke-model-switch)
    smoke_model_switch "$TARGET_PROJECT_DIR"
    ;;
  smoke-delegate-resume)
    smoke_delegate_resume "$TARGET_PROJECT_DIR"
    ;;
  smoke-compaction)
    smoke_compaction "$TARGET_PROJECT_DIR"
    ;;
  check-bridge)
    check_bridge
    ;;
  check-native-async)
    check_native_async
    ;;
  sentinel)
    shift || true
    sentinel_run "$@"
    ;;
  session-messaging)
    shift || true
    session_messaging_run "$@"
    ;;
  check-mcp)
    check_mcp
    ;;
  check-backends)
    check_backends
    ;;
  check-registration)
    check_registration
    ;;
  check-models)
    check_models
    ;;
  check-compaction-handoff)
    check_compaction_handoff
    ;;
  check-claude-sessions)
    check_claude_sessions "$TARGET_PROJECT_DIR"
    ;;
  verify-resume)
    verify_resume "$TARGET_PROJECT_DIR"
    ;;
  sync-auth)
    sync_auth
    ;;
  install)
    install_local_package "$TARGET_PROJECT_DIR"
    ;;
  remove)
    remove_local_package "$TARGET_PROJECT_DIR"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
