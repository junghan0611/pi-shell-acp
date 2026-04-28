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
  ./run.sh smoke-entwurf-resume [project-dir] # bridge-level entwurf-style continuity gate (Claude=resume, Codex=load)
  ./run.sh check-bridge               # pi-tools-bridge direct MCP smoke + test.sh + ACP visibility/invocation (claude+codex)
  ./run.sh check-native-async         # pi-native async entwurf spawn smoke (pi -e pi-extensions/entwurf.ts)
  ./run.sh sentinel [args...]         # entwurf 6-cell diagonal matrix (sync+resume × parent×target)
  ./run.sh session-messaging [args...] # 4-case session-messaging smoke (native/ACP cross-matrix)
  ./run.sh check-mcp                  # local deterministic check of normalizeMcpServers() — no Claude/ACP subprocess
  ./run.sh check-backends             # local deterministic check of backend launch resolution + backend-specific _meta shape
  ./run.sh check-registration         # local deterministic check of per-runtime provider registration semantics
  ./run.sh check-dep-versions         # local deterministic check that version pins (package.json/run.sh/README.md) agree
  ./run.sh check-models               # local deterministic check of MODELS contextWindow defaults (sonnet 200K, opus 1M) + override
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

# --- packages[] registration --------------------------------------------------
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

# --- piShellAcpProvider.mcpServers bundled entries ---------------------------
# Ship the two in-repo MCP adapters pre-wired so `pi install` produces a
# working setup without the consumer hand-editing settings.json. User-authored
# overrides (different command/args) are preserved untouched.
provider = data.setdefault("piShellAcpProvider", {})
if not isinstance(provider, dict):
    raise SystemExit("piShellAcpProvider is not an object")
servers = provider.setdefault("mcpServers", {})
if not isinstance(servers, dict):
    raise SystemExit("piShellAcpProvider.mcpServers is not an object")

BUNDLED = ("pi-tools-bridge", "session-bridge")
for name in BUNDLED:
    desired_cmd = f"{repo_dir}/mcp/{name}/start.sh"
    desired = {"command": desired_cmd, "args": []}
    existing = servers.get(name)
    if existing is None:
        servers[name] = desired
        print(f"install: added piShellAcpProvider.mcpServers.{name}")
    elif isinstance(existing, dict) and existing.get("command") == desired_cmd:
        # Already managed by us at the current repo path. Add the default args
        # field when missing, but never overwrite user-customized args.
        if "args" not in existing:
            existing["args"] = []
            print(f"install: normalized piShellAcpProvider.mcpServers.{name}.args -> []")
        elif existing.get("args") != []:
            print(f"install: preserved piShellAcpProvider.mcpServers.{name}.args (custom args)")
    else:
        cmd_repr = existing.get("command") if isinstance(existing, dict) else existing
        print(f"install: preserved piShellAcpProvider.mcpServers.{name} (user override: {cmd_repr})")

settings_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"install: updated {settings_path}")
print(f"install: package source -> {repo_dir}")
PY
  ensure_agent_dir_symlinks
}

# Ensure agent-level resources that pi-shell-acp code reads from
# ~/.pi/agent/ are wired up at install time. Currently:
#   - entwurf-targets.json — pi-extensions/lib/entwurf-core.ts reads
#     ~/.pi/agent/entwurf-targets.json. The package ships the canonical
#     version at $REPO_DIR/pi/entwurf-targets.json. Without this symlink
#     any entwurf tool call throws EntwurfRegistryError (lazy load — no
#     surface during plain `pi --model ...` runs but blocks delegation
#     immediately when the operator first calls entwurf).
#
# Idempotent — preserves an operator's existing file/symlink without
# overwriting. Lazy load means new symlinks are picked up on next entwurf
# call without restarting any running pi process.
ensure_agent_dir_symlinks() {
  local agent_dir="$HOME/.pi/agent"
  mkdir -p "$agent_dir"

  local target="$REPO_DIR/pi/entwurf-targets.json"
  local link="$agent_dir/entwurf-targets.json"

  if [ -L "$link" ]; then
    if [ "$(readlink "$link")" = "$target" ]; then
      :  # already correct, silent
    else
      echo "install: preserved $link (operator override -> $(readlink "$link"))"
    fi
  elif [ -e "$link" ]; then
    echo "install: preserved $link (operator file)"
  elif [ -f "$target" ]; then
    ln -s "$target" "$link"
    echo "install: linked $link -> $target"
  fi
}

remove_local_package() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")
  python3 - "$project_dir/.pi/settings.json" "$REPO_DIR" <<'PY'
import json, sys
from pathlib import Path

settings_path = Path(sys.argv[1])
repo_dir = str(Path(sys.argv[2]).resolve())
if not settings_path.exists():
    print(f"remove: nothing to do ({settings_path} missing)")
    raise SystemExit(0)

data = json.loads(settings_path.read_text())
if not isinstance(data, dict):
    raise SystemExit("settings.json is not an object")

# --- packages[] cleanup -------------------------------------------------------
packages = data.get("packages")
pkg_removed = 0
if isinstance(packages, list):
    filtered = []
    for item in packages:
        source = item.get("source") if isinstance(item, dict) else item
        if isinstance(source, str) and ("pi-shell-acp" in source):
            pkg_removed += 1
            continue
        filtered.append(item)
    data["packages"] = filtered

# --- piShellAcpProvider.mcpServers cleanup ------------------------------------
# Only remove entries that look like they came from ./run.sh install: either
# the command matches the current $REPO_DIR anchor exactly, or it ends with
# the bundled "/pi-shell-acp/mcp/<name>/start.sh" pattern (covers a rebuilt
# checkout under a different directory). Anything else is treated as a user
# override and left in place.
BUNDLED = ("pi-tools-bridge", "session-bridge")
provider = data.get("piShellAcpProvider")
mcp_removed = 0
if isinstance(provider, dict):
    servers = provider.get("mcpServers")
    if isinstance(servers, dict):
        for name in BUNDLED:
            existing = servers.get(name)
            if not isinstance(existing, dict):
                continue
            cmd = existing.get("command")
            if not isinstance(cmd, str):
                continue
            exact = cmd == f"{repo_dir}/mcp/{name}/start.sh"
            pattern = cmd.endswith(f"/pi-shell-acp/mcp/{name}/start.sh")
            if exact or pattern:
                del servers[name]
                mcp_removed += 1
                print(f"remove: removed piShellAcpProvider.mcpServers.{name}")
            else:
                print(f"remove: preserved piShellAcpProvider.mcpServers.{name} (user override: {cmd})")
        if not servers:
            provider.pop("mcpServers", None)
    if not provider:
        data.pop("piShellAcpProvider", None)

settings_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"remove: removed {pkg_removed} packages[] entries, {mcp_removed} mcpServers entries from {settings_path}")
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
  tools: ['Read', 'Bash', 'Edit', 'Write'],
  skillPlugins: [],
  permissionAllow: ['Read(*)', 'Bash(*)', 'Edit(*)', 'Write(*)', 'mcp__*'],
  disallowedTools: [],
  codexDisabledFeatures: [],
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
  tools: ['Read', 'Bash', 'Edit', 'Write'],
  skillPlugins: [],
  permissionAllow: ['Read(*)', 'Bash(*)', 'Edit(*)', 'Write(*)', 'mcp__*'],
  disallowedTools: [],
  codexDisabledFeatures: [],
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
  tools: ['Read', 'Bash', 'Edit', 'Write'],
  skillPlugins: [],
  permissionAllow: ['Read(*)', 'Bash(*)', 'Edit(*)', 'Write(*)', 'mcp__*'],
  disallowedTools: [],
  codexDisabledFeatures: [],
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

smoke_entwurf_resume_single() {
  local project_dir=$1
  local backend=$2
  local model=$3
  local expected_path=$4
  local label=$5

  local session_file
  session_file=$(mktemp /tmp/pi-shell-acp-entwurf-resume-XXXXXX.jsonl)

  echo "[smoke-entwurf-resume/$backend] ${label}"
  echo "[smoke-entwurf-resume/$backend] model=$model expected-turn2=$expected_path session=$session_file"

  local turn1_log turn1_rc=0
  turn1_log=$(cd "$project_dir" && PI_SHELL_ACP_STRICT_BOOTSTRAP=1 pi \
    --mode json -p --no-extensions \
    -e "$REPO_DIR" \
    --provider pi-shell-acp \
    --model "$model" \
    --session "$session_file" \
    'READY 만 답해' 2>&1) || turn1_rc=$?
  if [[ "$turn1_rc" != "0" ]]; then
    echo "[smoke-entwurf-resume/$backend] turn1 pi invocation failed rc=$turn1_rc:" >&2
    echo "$turn1_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if ! grep -q "^\[pi-shell-acp:bootstrap\] path=new backend=$backend" <<< "$turn1_log"; then
    echo "[smoke-entwurf-resume/$backend] turn1 expected path=new, got:" >&2
    echo "$turn1_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  local turn1_acp
  turn1_acp=$(grep -oE "^\[pi-shell-acp:bootstrap\] path=new backend=$backend [^$]*" <<< "$turn1_log" \
    | head -1 | grep -oE 'acpSessionId=[^ ]+' | head -1 | cut -d= -f2)
  if [[ -z "$turn1_acp" ]]; then
    echo "[smoke-entwurf-resume/$backend] turn1 acpSessionId not extractable:" >&2
    echo "$turn1_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if ! grep -qE '"role":"assistant"' "$session_file"; then
    echo "[smoke-entwurf-resume/$backend] turn1 session file has no assistant message" >&2
    cat "$session_file" >&2
    rm -f "$session_file"
    exit 1
  fi
  echo "[smoke-entwurf-resume/$backend] turn1 path=new acpSessionId=$turn1_acp: ok"

  local turn2_log turn2_rc=0
  turn2_log=$(cd "$project_dir" && PI_SHELL_ACP_STRICT_BOOTSTRAP=1 pi \
    --mode json -p --no-extensions \
    -e "$REPO_DIR" \
    --provider pi-shell-acp \
    --model "$model" \
    --session "$session_file" \
    'OK 만 답해' 2>&1) || turn2_rc=$?
  if [[ "$turn2_rc" != "0" ]]; then
    echo "[smoke-entwurf-resume/$backend] turn2 pi invocation failed rc=$turn2_rc:" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if ! grep -q "^\[pi-shell-acp:bootstrap\] path=$expected_path backend=$backend" <<< "$turn2_log"; then
    echo "[smoke-entwurf-resume/$backend] turn2 expected path=$expected_path, got:" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  local turn2_acp
  turn2_acp=$(grep -oE "^\[pi-shell-acp:bootstrap\] path=$expected_path backend=$backend [^$]*" <<< "$turn2_log" \
    | head -1 | grep -oE 'acpSessionId=[^ ]+' | head -1 | cut -d= -f2)
  if [[ "$turn2_acp" != "$turn1_acp" ]]; then
    echo "[smoke-entwurf-resume/$backend] acpSessionId mismatch turn1=$turn1_acp turn2=$turn2_acp" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if grep -q "^\[pi-shell-acp:bootstrap-invalidate\]" <<< "$turn2_log"; then
    echo "[smoke-entwurf-resume/$backend] turn2 unexpected bootstrap-invalidate:" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi
  if grep -q "^\[pi-shell-acp:bootstrap-fallback\]" <<< "$turn2_log"; then
    echo "[smoke-entwurf-resume/$backend] turn2 unexpected bootstrap-fallback:" >&2
    echo "$turn2_log" >&2
    rm -f "$session_file"
    exit 1
  fi

  # assistant message from turn2 must land in the same session file
  local assistant_count
  assistant_count=$(grep -cE '"role":"assistant"' "$session_file" || true)
  if [[ "${assistant_count:-0}" -lt 2 ]]; then
    echo "[smoke-entwurf-resume/$backend] expected >=2 assistant messages in session file, got ${assistant_count:-0}" >&2
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
    echo "[smoke-entwurf-resume/$backend] last assistant payload is empty (len=${last_assistant_len:-0})" >&2
    cat "$session_file" >&2
    rm -f "$session_file"
    exit 1
  fi
  echo "[smoke-entwurf-resume/$backend] turn2 path=$expected_path acpSessionId=$turn2_acp (same as turn1, last-assistant-len=$last_assistant_len): ok"

  rm -f "$session_file"
}

smoke_entwurf_resume() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")

  require_cmd pi

  echo "[smoke-entwurf-resume] bridge-level dual-backend continuity gate"
  echo "[smoke-entwurf-resume] project: $project_dir"
  echo "[smoke-entwurf-resume] repo:    $REPO_DIR"
  echo "[smoke-entwurf-resume] scope:   bridge carries same-session turn1->turn2 via resume(Claude) / load(Codex)"
  echo "                       — spawn authority / target selection / parent×target matrix live in"
  echo "                         this repo's entwurf surface (pi/entwurf-targets.json + mcp/pi-tools-bridge)."
  echo "                         This smoke validates BRIDGE carry only; orchestration is validated separately."

  smoke_entwurf_resume_single "$project_dir" claude claude-sonnet-4-6 resume "bridge continuity (Claude → resumeSession)"
  smoke_entwurf_resume_single "$project_dir" codex  gpt-5.2           load   "bridge continuity (Codex → loadSession)"

  echo "[smoke-entwurf-resume] Claude(resume) + Codex(load) bridge continuity: ok"
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
import { buildSessionMetaForBackend, CLAUDE_CONFIG_OVERLAY_DIR, CODEX_CONFIG_OVERLAY_DIR, ensureClaudeConfigOverlay, ensureCodexConfigOverlay, resolveAcpBackendLaunch } from './acp-bridge.ts';
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, readlinkSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';

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

  // Codex override path appends two argument groups in order:
  //   1. Codex mode flags (-c approval_policy=… -c sandbox_mode=…) chosen
  //      by resolveCodexMode(). Default = "full-access" — pi-YOLO parity
  //      with the Claude side and the only preset that lets workspace-
  //      external files (e.g. ~/.gnupg/ for gogcli) reach the agent.
  //   2. Auto-compaction guard (-c model_auto_compact_token_limit=i64::MAX),
  //      so silent backend compaction stays disabled even when
  //      CODEX_ACP_COMMAND replaces the launch command. Order matters:
  //      operators who set CODEX_ACP_COMMAND can re-pass earlier `-c`
  //      flags to override our mode while we still pin the compact guard
  //      after.
  const codexLaunch = resolveAcpBackendLaunch('codex');
  assert.equal(codexLaunch.command, 'bash');
  assert.deepEqual(codexLaunch.args, [
    '-lc',
    `${codexOverride} '-c' 'approval_policy=never' '-c' 'sandbox_mode=danger-full-access' '-c' 'model_auto_compact_token_limit=9223372036854775807' '-c' 'web_search="disabled"' '-c' 'tools.view_image=false' '-c' 'memories.generate_memories=false' '-c' 'memories.use_memories=false' '-c' 'history.persistence="none"' '-c' 'features.image_generation=false' '-c' 'features.tool_suggest=false' '-c' 'features.tool_search=false' '-c' 'features.multi_agent=false' '-c' 'features.apps=false' '-c' 'features.memories=false'`,
  ]);
  assert.equal(codexLaunch.source, 'env:CODEX_ACP_COMMAND');
  // Defense-in-depth: pin web_search=disabled, tools.view_image=false, and
  // four `features.*=false` flags even though the CODEX_HOME overlay
  // already strips operator config. codex-rs lets later -c values for the
  // same key win, so these flags hold even if the operator inlines
  // counter-values (e.g. `-c features.multi_agent=true`) via
  // CODEX_ACP_COMMAND — ours come last.
  //
  // Each features flag aligns one tool family with pi's advertised
  // baseline; the assertions name the disabled tool so a regression in
  // codex-rs's gating path (key rename, default flip) shows up here, not
  // only in live verification.
  assert.ok(
    codexLaunch.args.some((arg) => arg.includes('web_search="disabled"')),
    'codex launch must pin web_search=disabled',
  );
  assert.ok(
    codexLaunch.args.some((arg) => arg.includes('tools.view_image=false')),
    'codex launch must attempt to disable tools.view_image (best-effort; codex-rs 0.124.0 has no consumer for this field, kept for forward-compat)',
  );
  assert.ok(
    codexLaunch.args.some((arg) => arg.includes('features.image_generation=false')),
    'codex launch must disable image_generation feature (suppresses image_gen tool)',
  );
  assert.ok(
    codexLaunch.args.some((arg) => arg.includes('features.tool_suggest=false')),
    'codex launch must disable tool_suggest feature (suppresses tool_suggest tool)',
  );
  assert.ok(
    codexLaunch.args.some((arg) => arg.includes('features.tool_search=false')),
    'codex launch must disable tool_search feature (suppresses deferred-MCP tool_search tool)',
  );
  assert.ok(
    codexLaunch.args.some((arg) => arg.includes('features.multi_agent=false')),
    'codex launch must disable multi_agent feature (suppresses spawn_agent / send_input / wait_agent / close_agent / resume_agent collab tools)',
  );
  assert.ok(
    codexLaunch.args.some((arg) => arg.includes('features.apps=false')),
    'codex launch must disable apps feature (suppresses auto-injected mcp__codex_apps__* MCP server bundle, e.g. codex_apps__github)',
  );

  // PI_SHELL_ACP_CODEX_MODE=auto opts into codex-rs's standard mode
  // (workspace-write sandbox, on-request approvals). Compaction guard
  // stays in place independently.
  const prevMode = process.env.PI_SHELL_ACP_CODEX_MODE;
  process.env.PI_SHELL_ACP_CODEX_MODE = 'auto';
  try {
    const codexLaunchAutoMode = resolveAcpBackendLaunch('codex');
    assert.deepEqual(codexLaunchAutoMode.args, [
      '-lc',
      `${codexOverride} '-c' 'approval_policy=on-request' '-c' 'sandbox_mode=workspace-write' '-c' 'model_auto_compact_token_limit=9223372036854775807' '-c' 'web_search="disabled"' '-c' 'tools.view_image=false' '-c' 'memories.generate_memories=false' '-c' 'memories.use_memories=false' '-c' 'history.persistence="none"' '-c' 'features.image_generation=false' '-c' 'features.tool_suggest=false' '-c' 'features.tool_search=false' '-c' 'features.multi_agent=false' '-c' 'features.apps=false' '-c' 'features.memories=false'`,
    ]);
  } finally {
    if (prevMode === undefined) delete process.env.PI_SHELL_ACP_CODEX_MODE;
    else process.env.PI_SHELL_ACP_CODEX_MODE = prevMode;
  }

  // Invalid PI_SHELL_ACP_CODEX_MODE values throw at the launch surface.
  // Silent fallback would land typos like "readonly" (no dash) on the
  // full-access default — exactly the wrong direction for a sandbox knob.
  // "Never warn. Throw." (AGENTS.md).
  process.env.PI_SHELL_ACP_CODEX_MODE = 'super-yolo';
  try {
    assert.throws(
      () => resolveAcpBackendLaunch('codex'),
      /Invalid PI_SHELL_ACP_CODEX_MODE=super-yolo/,
    );
  } finally {
    if (prevMode === undefined) delete process.env.PI_SHELL_ACP_CODEX_MODE;
    else process.env.PI_SHELL_ACP_CODEX_MODE = prevMode;
  }

  // PI_SHELL_ACP_ALLOW_COMPACTION=1 disables the codex auto-compaction
  // guard args at the launch surface — opt-out is single-source and
  // applies to override + default paths uniformly. Mode flags stay.
  const prevAllow = process.env.PI_SHELL_ACP_ALLOW_COMPACTION;
  process.env.PI_SHELL_ACP_ALLOW_COMPACTION = '1';
  try {
    const codexLaunchOptOut = resolveAcpBackendLaunch('codex');
    assert.deepEqual(codexLaunchOptOut.args, [
      '-lc',
      `${codexOverride} '-c' 'approval_policy=never' '-c' 'sandbox_mode=danger-full-access' '-c' 'web_search="disabled"' '-c' 'tools.view_image=false' '-c' 'memories.generate_memories=false' '-c' 'memories.use_memories=false' '-c' 'history.persistence="none"' '-c' 'features.image_generation=false' '-c' 'features.tool_suggest=false' '-c' 'features.tool_search=false' '-c' 'features.multi_agent=false' '-c' 'features.apps=false' '-c' 'features.memories=false'`,
    ]);
  } finally {
    if (prevAllow === undefined) delete process.env.PI_SHELL_ACP_ALLOW_COMPACTION;
    else process.env.PI_SHELL_ACP_ALLOW_COMPACTION = prevAllow;
  }

  // codexDisabledFeatures launch param — explicit empty list opts fully out
  // of the bridge's feature-gate policy (operators who set
  // `codexDisabledFeatures: []` in pi-shell-acp settings.json land here).
  // Static surface flags (web_search, tools.view_image) stay in place; only
  // the dynamic `features.*=false` portion drops out.
  const codexLaunchEmptyFeatures = resolveAcpBackendLaunch('codex', { codexDisabledFeatures: [] });
  assert.deepEqual(codexLaunchEmptyFeatures.args, [
    '-lc',
    `${codexOverride} '-c' 'approval_policy=never' '-c' 'sandbox_mode=danger-full-access' '-c' 'model_auto_compact_token_limit=9223372036854775807' '-c' 'web_search="disabled"' '-c' 'tools.view_image=false' '-c' 'memories.generate_memories=false' '-c' 'memories.use_memories=false' '-c' 'history.persistence="none"'`,
  ]);
  assert.ok(
    !codexLaunchEmptyFeatures.args.some((arg) => arg.includes('features.')),
    'codex launch with codexDisabledFeatures=[] must emit zero features.* gate flags',
  );

  // codexDisabledFeatures launch param — partial override. Operators can
  // narrow the policy to a single feature (e.g. just block apps, leave
  // image_gen registered) or extend it past the defaults. The launch path
  // emits exactly the keys passed, in order, with no de-duplication or
  // canonicalization (codex-rs validates keys at config load via
  // is_known_feature_key, so a typo surfaces as a startup warning).
  const codexLaunchPartialFeatures = resolveAcpBackendLaunch('codex', { codexDisabledFeatures: ['apps', 'multi_agent'] });
  assert.deepEqual(codexLaunchPartialFeatures.args, [
    '-lc',
    `${codexOverride} '-c' 'approval_policy=never' '-c' 'sandbox_mode=danger-full-access' '-c' 'model_auto_compact_token_limit=9223372036854775807' '-c' 'web_search="disabled"' '-c' 'tools.view_image=false' '-c' 'memories.generate_memories=false' '-c' 'memories.use_memories=false' '-c' 'history.persistence="none"' '-c' 'features.apps=false' '-c' 'features.multi_agent=false'`,
  ]);
  assert.ok(
    !codexLaunchPartialFeatures.args.some((arg) => arg.includes('features.image_generation')),
    'codex launch with codexDisabledFeatures=["apps","multi_agent"] must NOT emit features.image_generation',
  );

  // codexDeveloperInstructions launch param — pi-shell-acp's identity carrier
  // on the codex backend. Codex ACP does not honor `_meta.systemPrompt`, so
  // the codex `developer` role config slot is the highest stable identity
  // layer available to us. The rendered engraving must reach the spawned
  // codex-acp child as `-c developer_instructions="<TOML-escaped>"`,
  // appended after the static surface + feature-gate args. tomlBasicString
  // (= JSON.stringify) is the production escape path; the test re-runs it
  // to derive the expected fragment so the contract stays in lockstep.
  const codexDevInstrSample = 'line1\nline2 with "quote" and \\backslash';
  const codexLaunchWithDevInstr = resolveAcpBackendLaunch('codex', {
    codexDisabledFeatures: ['apps'],
    codexDeveloperInstructions: codexDevInstrSample,
  });
  const expectedDevInstrPair = `'-c' 'developer_instructions=${JSON.stringify(codexDevInstrSample)}'`;
  assert.ok(
    codexLaunchWithDevInstr.args[1].endsWith(expectedDevInstrPair),
    `codex launch must end with TOML-escaped developer_instructions pair; expected suffix=${expectedDevInstrPair} got=${codexLaunchWithDevInstr.args[1]}`,
  );
  assert.ok(
    JSON.stringify(codexDevInstrSample).includes('\\n'),
    'tomlBasicString contract: literal newline must be escaped as \\n',
  );
  assert.ok(
    JSON.stringify(codexDevInstrSample).includes('\\"'),
    'tomlBasicString contract: embedded double-quote must be escaped as \\"',
  );

  // Empty / undefined / whitespace-only codexDeveloperInstructions emits no
  // `-c developer_instructions=` flag — codex defaults apply (no
  // pi-authored developer instruction present).
  const codexLaunchNoDevInstr = resolveAcpBackendLaunch('codex', {
    codexDisabledFeatures: ['apps'],
    codexDeveloperInstructions: '   ',
  });
  assert.ok(
    !codexLaunchNoDevInstr.args[1].includes('developer_instructions'),
    'whitespace-only codexDeveloperInstructions must not emit a -c flag',
  );

  // Skill listing in the system prompt is gated by the SDK on
  // `tools.some(name === "Skill")` (claude-agent-sdk SN1 emitter, identical
  // in 0.2.114 and 0.2.119). loadProviderSettings() augments tools with
  // "Skill" and permissionAllow with "Skill(*)" whenever skillPlugins is
  // non-empty, so the params reaching buildSessionMetaForBackend in the
  // skill-plugins case look like this:
  const claudeMeta = buildSessionMetaForBackend('claude', {
    modelId: 'claude-sonnet-4-6',
    settingSources: [],
    strictMcpConfig: true,
    tools: ['Read', 'Bash', 'Edit', 'Write', 'Skill'],
    skillPlugins: ['/abs/path/to/skill-plugin'],
    permissionAllow: ['Bash(*)', 'Read(*)', 'Edit(*)', 'Write(*)', 'mcp__*', 'Skill(*)'],
    disallowedTools: [
      'AskUserQuestion',
      'CronCreate', 'CronDelete', 'CronList',
      'EnterPlanMode', 'EnterWorktree', 'ExitPlanMode', 'ExitWorktree',
      'Monitor',
      'NotebookEdit',
      'PushNotification',
      'RemoteTrigger',
      'TaskCreate', 'TaskGet', 'TaskList', 'TaskOutput', 'TaskStop', 'TaskUpdate',
      'WebFetch', 'WebSearch',
    ],
  }, 'system prompt');
  assert.equal(claudeMeta?.claudeCode?.options?.model, 'claude-sonnet-4-6');
  // settingSources empty by default — pi-shell-acp does not inherit filesystem
  // Claude Code settings; skills are delivered via plugins, MCP via mcpServers.
  assert.deepEqual(claudeMeta?.claudeCode?.options?.settingSources, []);
  // Tool surface is the explicit pi baseline plus Skill (added by
  // loadProviderSettings when skillPlugins is non-empty), so the SDK's
  // SN1 emitter actually produces a skill listing in the system prompt.
  assert.deepEqual(claudeMeta?.claudeCode?.options?.tools, ['Read', 'Bash', 'Edit', 'Write', 'Skill']);
  // Skills are injected as local plugins.
  assert.deepEqual(claudeMeta?.claudeCode?.options?.plugins, [
    { type: 'local', path: '/abs/path/to/skill-plugin' },
  ]);
  // Permission allowlist threads through `Options.settings.permissions.allow`.
  // Combined with claude-agent-acp's own permissionMode resolution, this
  // delivers de facto YOLO for the listed tools without flipping the user's
  // native ~/.claude/settings.json defaultMode. Skill(*) is included so the
  // listing surface is not silently denied at the permission layer.
  assert.deepEqual(claudeMeta?.claudeCode?.options?.settings?.permissions?.allow, [
    'Bash(*)',
    'Read(*)',
    'Edit(*)',
    'Write(*)',
    'mcp__*',
    'Skill(*)',
  ]);
  // Disallowed tools — full deferred set passes through verbatim. The SDK's
  // skill-listing emitter is gated on `tools.includes("Skill")`, but the
  // separate deferred-tool advertisement surface (system-reminder block
  // listing tools available via ToolSearch) bypasses Options.tools and
  // requires Options.disallowedTools to suppress.
  assert.deepEqual(claudeMeta?.claudeCode?.options?.disallowedTools, [
    'AskUserQuestion',
    'CronCreate', 'CronDelete', 'CronList',
    'EnterPlanMode', 'EnterWorktree', 'ExitPlanMode', 'ExitWorktree',
    'Monitor',
    'NotebookEdit',
    'PushNotification',
    'RemoteTrigger',
    'TaskCreate', 'TaskGet', 'TaskList', 'TaskOutput', 'TaskStop', 'TaskUpdate',
    'WebFetch', 'WebSearch',
  ]);
  // _meta.systemPrompt is delivered as a *string*, not as { append: ... }.
  // claude-agent-acp interprets a string-form systemPrompt as a full preset
  // replacement (acp-agent.ts:1685), so the claude_code preset's per-cwd
  // dynamic sections (working directory, auto-memory path, git status,
  // todo handling) drop out of the system prompt. The engraving alone
  // carries identity context above Anthropic's SDK-level minimum prefix.
  assert.deepEqual(claudeMeta?.systemPrompt, 'system prompt');
  assert.equal(claudeMeta?.claudeCode?.options?.extraArgs?.['strict-mcp-config'], null);

  // Empty skillPlugins => no plugins field emitted, no Skill auto-added.
  // Empty disallowedTools => no disallowedTools field emitted (escape hatch
  // for operators who explicitly opt back into the SDK's deferred-tool
  // advertisement). (loadProviderSettings would not augment
  // tools/permissionAllow either.)
  const claudeMetaNoPlugins = buildSessionMetaForBackend('claude', {
    modelId: 'claude-sonnet-4-6',
    settingSources: [],
    strictMcpConfig: true,
    tools: ['Read', 'Bash', 'Edit', 'Write'],
    skillPlugins: [],
    permissionAllow: ['Bash(*)', 'mcp__*'],
    disallowedTools: [],
  }, undefined);
  assert.equal(claudeMetaNoPlugins?.claudeCode?.options?.plugins, undefined);
  assert.deepEqual(claudeMetaNoPlugins?.claudeCode?.options?.tools, ['Read', 'Bash', 'Edit', 'Write']);
  assert.equal(claudeMetaNoPlugins?.claudeCode?.options?.disallowedTools, undefined);

  const codexMeta = buildSessionMetaForBackend('codex', {
    modelId: 'codex-mini-latest',
    settingSources: ['user'],
    strictMcpConfig: true,
    tools: ['Read', 'Bash', 'Edit', 'Write'],
    skillPlugins: [],
    permissionAllow: [],
    disallowedTools: [],
  }, 'system prompt');
  assert.equal(codexMeta, undefined);

  assert.throws(() => resolveAcpBackendLaunch(undefined), /ACP backend is required\./);
  assert.throws(() => resolveAcpBackendLaunch('bogus'), /Unknown ACP backend: bogus\./);

  // Claude config overlay — isolate claude-agent-acp's SettingsManager from
  // ~/.claude/settings.json's permissionMode pickup. We rebuild the overlay
  // on every claude session bootstrap (idempotent symlink farm + minimal
  // settings.json) and point CLAUDE_CONFIG_DIR at it via bridgeEnvDefaults.
  assert.equal(typeof CLAUDE_CONFIG_OVERLAY_DIR, 'string');
  assert.ok(CLAUDE_CONFIG_OVERLAY_DIR.endsWith('claude-config-overlay'),
    'overlay dir constant must point at the pi-owned claude-config-overlay path');

  // Exercise ensureClaudeConfigOverlay against a synthetic real/overlay pair
  // so the production filesystem stays untouched.
  const overlayTestRoot = join(tmpdir(), `pi-shell-acp-overlay-${Date.now()}`);
  const realDir = join(overlayTestRoot, 'real');
  const overlayDir = join(overlayTestRoot, 'overlay');
  try {
    mkdirSync(realDir, { recursive: true });
    // Seed the synthetic real dir with shapes the production overlay should
    // mirror: a settings.json (overridden, NOT symlinked), a credentials
    // file (symlinked passthrough), a projects/ tree carrying an
    // operator-side MEMORY.md (must NOT pass through — overlay creates its
    // own empty projects/), and a non-whitelisted entry like hooks/ (must
    // be wiped by the stale-cleanup loop, not symlinked through).
    writeFileSync(join(realDir, 'settings.json'), JSON.stringify({ permissions: { defaultMode: 'auto' } }), 'utf8');
    writeFileSync(join(realDir, '.credentials.json'), '{"token":"test"}', 'utf8');
    mkdirSync(join(realDir, 'projects', 'operator-cwd', 'memory'), { recursive: true });
    writeFileSync(join(realDir, 'projects', 'operator-cwd', 'memory', 'MEMORY.md'), 'OPERATOR-LEAK-CANARY', 'utf8');
    mkdirSync(join(realDir, 'hooks'), { recursive: true });
    writeFileSync(join(realDir, 'hooks', 'preToolUse.sh'), '#!/bin/sh\nexit 0\n', 'utf8');

    ensureClaudeConfigOverlay(realDir, overlayDir);

    // settings.json must be authored, not symlinked, and contain our override.
    const settingsStat = lstatSync(join(overlayDir, 'settings.json'));
    assert.equal(settingsStat.isSymbolicLink(), false,
      'overlay settings.json must be a regular file authored by pi-shell-acp, not a symlink');
    const overlaySettings = JSON.parse(readFileSync(join(overlayDir, 'settings.json'), 'utf8'));
    assert.equal(overlaySettings.permissions?.defaultMode, 'default',
      'overlay settings.json must pin permissions.defaultMode to "default"');
    assert.equal(overlaySettings.autoMemoryEnabled, false,
      'overlay settings.json must opt out of the SDK auto-memory subsystem');

    // Whitelisted entries pass through as symlinks to the operator's real dir.
    const credStat = lstatSync(join(overlayDir, '.credentials.json'));
    assert.equal(credStat.isSymbolicLink(), true);
    assert.equal(readlinkSync(join(overlayDir, '.credentials.json')), join(realDir, '.credentials.json'));

    // projects/ is overlay-private — an empty directory, NOT a symlink to
    // the operator's tree. Closes the per-cwd MEMORY.md auto-injection
    // channel: the binary's sanitized-cwd lookup finds nothing here.
    const projStat = lstatSync(join(overlayDir, 'projects'));
    assert.equal(projStat.isSymbolicLink(), false,
      'overlay projects/ must be an overlay-private directory, not a symlink to operator data');
    assert.equal(projStat.isDirectory(), true);
    const projContents = readdirSync(join(overlayDir, 'projects'));
    assert.deepEqual(projContents, [],
      'overlay projects/ must start empty — operator MEMORY.md must not leak through');
    assert.equal(existsSync(join(overlayDir, 'projects', 'operator-cwd', 'memory', 'MEMORY.md')), false,
      'operator-side MEMORY.md must not be reachable through the overlay');

    // Non-whitelisted entries (operator hooks, agents, sessions data,
    // settings.local.json with personal env, ...) must NOT appear in the
    // overlay. The stale-cleanup loop guarantees this each bootstrap.
    assert.equal(existsSync(join(overlayDir, 'hooks')), false,
      'overlay must not expose operator hooks/ — execution surface leak');

    // Idempotence: a second call must succeed without throwing and preserve
    // the same shape (still no operator data, still empty projects/).
    ensureClaudeConfigOverlay(realDir, overlayDir);
    assert.equal(readlinkSync(join(overlayDir, '.credentials.json')), join(realDir, '.credentials.json'));
    assert.equal(existsSync(join(overlayDir, 'hooks')), false,
      'second-call idempotence must not let operator hooks/ leak back in');
  } finally {
    rmSync(overlayTestRoot, { recursive: true, force: true });
  }

  // Codex config overlay — mirror of the Claude overlay above. Shields
  // codex-acp's Config loader from ~/.codex/config.toml fields the operator
  // sets for their personal codex use (model, model_reasoning_effort,
  // personality, projects.trust_level, [notice.*]). pi-shell-acp pins every
  // operating-surface knob it cares about via -c CLI flags; the overlay's
  // config.toml is intentionally minimal so unpinned fields fall through to
  // codex-rs defaults rather than to the operator's preferences.
  assert.equal(typeof CODEX_CONFIG_OVERLAY_DIR, 'string');
  assert.ok(CODEX_CONFIG_OVERLAY_DIR.endsWith('codex-config-overlay'),
    'overlay dir constant must point at the pi-owned codex-config-overlay path');

  const codexOverlayTestRoot = join(tmpdir(), `pi-shell-acp-codex-overlay-${Date.now()}`);
  const codexRealDir = join(codexOverlayTestRoot, 'real');
  const codexOverlayDir = join(codexOverlayTestRoot, 'overlay');
  try {
    mkdirSync(codexRealDir, { recursive: true });
    // Seed the synthetic real dir with shapes the production overlay must
    // mirror or reject:
    //   - config.toml that, if inherited, would leak `model` and `personality`
    //     through to pi-shell-acp sessions (overlay authors its own minimal
    //     replacement instead)
    //   - auth.json + skills/ — whitelist passthrough (codex can't run
    //     without auth; skills is the deliberately-shared registry holding
    //     both binary built-ins and operator agent-config symlinks)
    //   - memories/, sessions/ carrying operator-side payload — must NOT
    //     pass through; overlay creates its own empty trees so codex's
    //     per-cwd memory/session lookups find nothing leakable.
    //   - history.jsonl + rules/ — non-whitelisted entries (operator command
    //     history + operator policy/execution rules); must be wiped by the
    //     stale-cleanup loop, not symlinked through.
    writeFileSync(join(codexRealDir, 'config.toml'), 'model = "leak-me"\npersonality = "leak"\n', 'utf8');
    writeFileSync(join(codexRealDir, 'auth.json'), '{"token":"test"}', 'utf8');
    mkdirSync(join(codexRealDir, 'skills'), { recursive: true });
    mkdirSync(join(codexRealDir, 'memories'), { recursive: true });
    writeFileSync(join(codexRealDir, 'memories', 'operator-notes.md'), 'OPERATOR-MEMORY-CANARY', 'utf8');
    mkdirSync(join(codexRealDir, 'sessions'), { recursive: true });
    writeFileSync(join(codexRealDir, 'sessions', 'old-session.json'), '{"sessionId":"OPERATOR-SESSION-CANARY"}', 'utf8');
    writeFileSync(join(codexRealDir, 'history.jsonl'), '{"cmd":"OPERATOR-HISTORY-CANARY"}\n', 'utf8');
    mkdirSync(join(codexRealDir, 'rules'), { recursive: true });
    writeFileSync(join(codexRealDir, 'rules', 'policy.md'), 'OPERATOR-RULE-CANARY', 'utf8');
    // codex auto-loads ~/.codex/AGENTS.md as global user instructions
    // (codex-rs/agents_md.rs); the overlay must NOT expose the operator's
    // file. The cleanup loop wipes anything not on the allowlist, so this
    // canary verifies AGENTS.md is treated as an operator-personal entry.
    writeFileSync(join(codexRealDir, 'AGENTS.md'), '# OPERATOR-AGENTS-MD-CANARY\n', 'utf8');
    // state_5.sqlite is codex's thread/memory state DB
    // (codex-rs/state/runtime.rs). Symlinking it through would leak the
    // operator's persistent thread + memory store into pi-shell-acp
    // sessions — the deepest leak channel on the codex backend. logs_2.sqlite
    // is a similar telemetry DB with operator activity. Both must NOT
    // pass through; they belong to OVERLAY_BINARY_OWNED_CODEX so codex
    // initializes fresh copies inside the overlay.
    writeFileSync(join(codexRealDir, 'state_5.sqlite'), 'OPERATOR-STATE-CANARY', 'utf8');
    writeFileSync(join(codexRealDir, 'state_5.sqlite-shm'), 'OPERATOR-STATE-SHM-CANARY', 'utf8');
    writeFileSync(join(codexRealDir, 'state_5.sqlite-wal'), 'OPERATOR-STATE-WAL-CANARY', 'utf8');
    writeFileSync(join(codexRealDir, 'logs_2.sqlite'), 'OPERATOR-LOGS-CANARY', 'utf8');
    // log/ and shell_snapshots/ carry per-cwd operator activity. Belong
    // to OVERLAY_EMPTY_DIRS_CODEX (overlay-private empty trees).
    mkdirSync(join(codexRealDir, 'log'), { recursive: true });
    writeFileSync(join(codexRealDir, 'log', 'session.log'), 'OPERATOR-LOG-CANARY', 'utf8');
    mkdirSync(join(codexRealDir, 'shell_snapshots'), { recursive: true });
    writeFileSync(join(codexRealDir, 'shell_snapshots', 'snap.json'), 'OPERATOR-SHELL-CANARY', 'utf8');

    ensureCodexConfigOverlay(codexRealDir, codexOverlayDir);

    // config.toml: regular file, NOT symlink, NOT inheriting operator content.
    const configStat = lstatSync(join(codexOverlayDir, 'config.toml'));
    assert.equal(configStat.isSymbolicLink(), false,
      'overlay config.toml must be a regular file authored by pi-shell-acp, not a symlink');
    const overlayContent = readFileSync(join(codexOverlayDir, 'config.toml'), 'utf8');
    assert.ok(!overlayContent.includes('leak-me'),
      'overlay config.toml must not inherit operator model setting');
    assert.ok(!overlayContent.includes('personality'),
      'overlay config.toml must not inherit operator personality setting');

    // Whitelisted entries pass through as symlinks to the operator's real dir.
    const codexAuthStat = lstatSync(join(codexOverlayDir, 'auth.json'));
    assert.equal(codexAuthStat.isSymbolicLink(), true);
    assert.equal(readlinkSync(join(codexOverlayDir, 'auth.json')), join(codexRealDir, 'auth.json'));
    const codexSkillsStat = lstatSync(join(codexOverlayDir, 'skills'));
    assert.equal(codexSkillsStat.isSymbolicLink(), true);
    assert.equal(readlinkSync(join(codexOverlayDir, 'skills')), join(codexRealDir, 'skills'));

    // memories/ and sessions/ are overlay-private — empty directories, NOT
    // symlinks to the operator's tree. Closes the per-cwd memory and session
    // leak channels: codex's lookups through CODEX_HOME find empty trees.
    const memStat = lstatSync(join(codexOverlayDir, 'memories'));
    assert.equal(memStat.isSymbolicLink(), false,
      'overlay memories/ must be an overlay-private directory, not a symlink to operator data');
    assert.equal(memStat.isDirectory(), true);
    assert.deepEqual(readdirSync(join(codexOverlayDir, 'memories')), [],
      'overlay memories/ must start empty — operator memory must not leak through');
    assert.equal(existsSync(join(codexOverlayDir, 'memories', 'operator-notes.md')), false,
      'operator-side memory file must not be reachable through the overlay');

    const sessStat = lstatSync(join(codexOverlayDir, 'sessions'));
    assert.equal(sessStat.isSymbolicLink(), false,
      'overlay sessions/ must be an overlay-private directory, not a symlink to operator data');
    assert.equal(sessStat.isDirectory(), true);
    assert.deepEqual(readdirSync(join(codexOverlayDir, 'sessions')), [],
      'overlay sessions/ must start empty — operator session data must not leak through');
    assert.equal(existsSync(join(codexOverlayDir, 'sessions', 'old-session.json')), false,
      'operator-side session file must not be reachable through the overlay');

    // Non-whitelisted entries must NOT appear in the overlay. The stale-
    // cleanup loop guarantees this each bootstrap. rules/ is especially
    // important: it would leak operator policy / execution rules, not just
    // narrative memory. AGENTS.md would auto-load as user instructions
    // via codex-rs/agents_md.rs.
    assert.equal(existsSync(join(codexOverlayDir, 'history.jsonl')), false,
      'overlay must not expose operator history.jsonl — command-history leak');
    assert.equal(existsSync(join(codexOverlayDir, 'rules')), false,
      'overlay must not expose operator rules/ — execution-policy leak');
    assert.equal(existsSync(join(codexOverlayDir, 'AGENTS.md')), false,
      'overlay must not expose operator AGENTS.md — auto-loaded user-instruction leak');

    // log/ and shell_snapshots/: overlay-private empty directories.
    // operator-side payloads must not be reachable through the overlay.
    const logStat = lstatSync(join(codexOverlayDir, 'log'));
    assert.equal(logStat.isSymbolicLink(), false,
      'overlay log/ must be an overlay-private directory, not a symlink to operator data');
    assert.equal(logStat.isDirectory(), true);
    assert.equal(existsSync(join(codexOverlayDir, 'log', 'session.log')), false,
      'operator-side log payload must not be reachable through the overlay');
    const shellStat = lstatSync(join(codexOverlayDir, 'shell_snapshots'));
    assert.equal(shellStat.isSymbolicLink(), false,
      'overlay shell_snapshots/ must be an overlay-private directory, not a symlink to operator data');
    assert.equal(shellStat.isDirectory(), true);
    assert.equal(existsSync(join(codexOverlayDir, 'shell_snapshots', 'snap.json')), false,
      'operator-side shell snapshot must not be reachable through the overlay');

    // state_5.sqlite* and logs_2.sqlite — codex thread/memory state DB +
    // telemetry DB. NOT in passthrough; codex initializes fresh copies
    // inside the overlay. Verify no symlink reaches the operator's real
    // file (the canary content must not be readable through the overlay
    // path). After ensureCodexConfigOverlay there should be either no
    // entry at all (codex will create on first launch) or an
    // overlay-owned regular file the cleanup loop preserves — in either
    // case the operator canary content must NOT be present.
    for (const dbName of ['state_5.sqlite', 'state_5.sqlite-shm', 'state_5.sqlite-wal', 'logs_2.sqlite']) {
      const overlayDbPath = join(codexOverlayDir, dbName);
      if (existsSync(overlayDbPath)) {
        const overlayDbStat = lstatSync(overlayDbPath);
        assert.equal(overlayDbStat.isSymbolicLink(), false,
          `overlay ${dbName} must not be a symlink to operator data`);
        const content = readFileSync(overlayDbPath, 'utf8');
        assert.ok(!content.includes('OPERATOR-'),
          `overlay ${dbName} must not carry operator canary content`);
      }
    }

    // Idempotence: a second call must succeed without throwing and preserve
    // the same isolation shape (still no operator data, still empty
    // memories/sessions trees).
    ensureCodexConfigOverlay(codexRealDir, codexOverlayDir);
    assert.equal(readlinkSync(join(codexOverlayDir, 'auth.json')), join(codexRealDir, 'auth.json'));
    assert.deepEqual(readdirSync(join(codexOverlayDir, 'memories')), [],
      'second-call idempotence must preserve empty memories/');
    assert.equal(existsSync(join(codexOverlayDir, 'rules')), false,
      'second-call idempotence must not let operator rules/ leak back in');
  } finally {
    rmSync(codexOverlayTestRoot, { recursive: true, force: true });
  }

  console.log('[check-backends] 86 assertions ok');
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

  # Run three times: defaults, explicit override, bogus override.
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

// --- Pass 1: curated surface + default Claude defaults ---
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

  // Claude defaults: sonnet stays at 200K, opus surfaces at 1M.
  {
    const sonnet = models.get('claude-sonnet-4-6');
    assert.ok(sonnet, 'curated Claude model missing: claude-sonnet-4-6');
    assert.equal(
      sonnet.contextWindow, 200000,
      `default: claude-sonnet-4-6 contextWindow should be 200000, got ${sonnet.contextWindow}`,
    );
  }
  for (const id of ['claude-opus-4-6', 'claude-opus-4-7']) {
    const m = models.get(id);
    if (!m) continue;
    assert.equal(
      m.contextWindow, 1000000,
      `default: ${id} contextWindow should be 1000000, got ${m.contextWindow}`,
    );
  }

  // Codex context metadata — source is openai-codex (NOT openai). The regression
  // that motivated this gate: reading from openai source made pi-shell-acp
  // advertise gpt-5.5 ctx=1,050,000 while the openai-codex source reflects what
  // codex-acp actually delivers. As of pi-ai 0.70.2 the entire openai-codex
  // gpt-5.x line declares 272,000.
  // Values below must match @mariozechner/pi-ai getModels("openai-codex") —
  // if upstream updates a context, update this gate with it.
  const CODEX_EXPECTED_CTX = {
    'gpt-5.2':      272000,
    'gpt-5.4':      272000,
    'gpt-5.4-mini': 272000,
    'gpt-5.5':      272000,
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

  console.log('[check-models] pass 1 (curated surface + Claude defaults + codex source): ok');
}

// --- Pass 2: explicit override respected ---
{
  const models = await collectModels('1000000');
  for (const id of ['claude-sonnet-4-6', 'claude-opus-4-7']) {
    const m = models.get(id);
    if (!m) continue;
    assert.equal(
      m.contextWindow,
      1_000_000,
      `override: ${id} contextWindow should be 1000000 with PI_SHELL_ACP_CLAUDE_CONTEXT=1000000, got ${m.contextWindow}`,
    );
  }
  console.log('[check-models] pass 2 (PI_SHELL_ACP_CLAUDE_CONTEXT=1000000 override): ok');
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

check_dep_versions() {
  # Catches version-pin drift across package.json, run.sh, and README.md.
  # Concretely the kind of skew that produced commit 21de0f9's "0.11.1
  # leftover" review comment: package.json bumped to 0.12.0 while README
  # and run.sh's setup gate still claimed 0.11.1. Static check, no
  # subprocess — fast enough to run inside `pnpm check` and pre-commit.
  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';

const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
const claudePinned = pkg.dependencies['@agentclientprotocol/claude-agent-acp'];
const codexPinned = pkg.dependencies['@zed-industries/codex-acp'];
assert.ok(claudePinned, 'package.json must pin @agentclientprotocol/claude-agent-acp');
assert.ok(codexPinned, 'package.json must pin @zed-industries/codex-acp');

// `^` + `m` flag anchors to the start-of-line shell assignment so we don't
// accidentally pick up the regex literal inside this very check function's
// heredoc (which is indented, so won't match `^...`).
const runSh = readFileSync('run.sh', 'utf8');
const claudeRequired = runSh.match(/^CLAUDE_ACP_REQUIRED_VERSION="([^"]+)"/m)?.[1];
const codexRequired = runSh.match(/^CODEX_ACP_REQUIRED_VERSION="([^"]+)"/m)?.[1];
assert.equal(claudeRequired, claudePinned,
  `run.sh CLAUDE_ACP_REQUIRED_VERSION (${claudeRequired}) must match package.json @agentclientprotocol/claude-agent-acp (${claudePinned})`);
assert.equal(codexRequired, codexPinned,
  `run.sh CODEX_ACP_REQUIRED_VERSION (${codexRequired}) must match package.json @zed-industries/codex-acp (${codexPinned})`);

const readme = readFileSync('README.md', 'utf8');
const readmeCodex = readme.match(/@zed-industries\/codex-acp@([0-9.]+)/)?.[1];
assert.equal(readmeCodex, codexPinned,
  `README.md @zed-industries/codex-acp install pin (${readmeCodex}) must match package.json (${codexPinned})`);

console.log('[check-dep-versions] 5 assertions ok');
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

// Two handlers per runtime: session_shutdown (bridge cleanup) and
// session_before_compact (compaction policy gate). Both attach exactly
// once per runtime — the second registerProviderExtension(runtimeA)
// call is guarded by isRegisteredOnRuntime/markRegisteredOnRuntime.
assert.equal(eventCalls.length, 4, 'lifecycle handlers should be attached once per runtime');
assert.deepEqual(eventCalls.map((call) => `${call.label}:${call.event}`), [
  'runtime-a:session_shutdown',
  'runtime-a:session_before_compact',
  'runtime-b:session_shutdown',
  'runtime-b:session_before_compact',
]);
assert.ok(eventCalls.every((call) => call.handlerType === 'function'), 'lifecycle handlers must be functions');

console.log('[check-registration] 8 assertions ok');
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

CLAUDE_ACP_REQUIRED_VERSION="0.31.0"
CODEX_ACP_REQUIRED_VERSION="0.12.0"

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
#   3. pi-native async entwurf spawn via `pi -e pi-extensions/entwurf.ts`
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

  # Bridge exposes a deliberately narrow set: session_search / knowledge_search
  # are intentionally NOT here — those are skill-side concerns (see mcp/pi-tools-bridge/src/index.ts header).
  for tool in entwurf_send entwurf_peers entwurf entwurf_resume; do
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

  if ! raw=$(cd "$REPO_DIR" && pi -e "$REPO_DIR" --provider pi-shell-acp --model "$model" -p 'entwurf_send 도구가 보이면 반드시 그 도구를 실제로 1회 호출해. target은 __definitely_does_not_exist__, message는 "ping", mode는 follow_up 으로 해. functions.send_input 같은 다른 도구는 절대 쓰지 마. 응답은 두 줄만: 1) TOOL:<사용한 도구명 또는 NONE> 2) RESULT:<성공/실패 핵심 메시지 한 줄>. 도구가 안 보이면 TOOL:NONE / RESULT:not visible 로만 답해.' ); then
    fail "pi-tools-bridge: $backend_label invocation smoke failed"
    return 1
  fi

  if [[ "$raw" != *"entwurf_send"* ]]; then
    echo "$raw" >&2
    fail "pi-tools-bridge: $backend_label invocation did not use entwurf_send"
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

  if [ ! -x "$bridge_dir/start.sh" ]; then
    fail "pi-tools-bridge: launcher missing at $bridge_dir/start.sh"
    return 1
  fi

  log "pi-tools-bridge: direct MCP smoke (strip-types launcher, no build step)"

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
  const expected = ['entwurf', 'entwurf_resume', 'entwurf_peers', 'entwurf_send'];
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

# pi-native async entwurf spawn smoke. Loads the native entwurf.ts directly
# and asks a cheap model to invoke `entwurf` in async mode against a bogus
# host. We read pi's --mode json event stream so the gate inspects the tool's
# *actual* sync return (which contains "Async entwurf spawned" + Task ID),
# not the model's natural-language interpretation. We also grep explicitly for
# the regression class PM flagged: a stale `explicitExtensions` reference in
# runEntwurfAsync would surface as a ReferenceError in the tool result.
validate_pi_native_async_entwurf() {
  local raw
  log "pi-native: async entwurf spawn smoke (model: gpt-5.4-mini)..."

  if ! raw=$(cd "$REPO_DIR" && pi -p \
              --mode json \
              --no-extensions \
              -e "$REPO_DIR/pi-extensions/entwurf.ts" \
              --provider openai-codex \
              --model gpt-5.4-mini \
              'entwurf 도구를 task="noop", host="__native_async_smoke_bogus__", mode="async" 인수로 정확히 1회 호출하라. 도구의 첫 sync 응답을 그대로 echo하라. 그 다음에 도착하는 follow-up 메시지는 무시하고 더 출력하지 마라.' 2>&1); then
    echo "$raw" >&2
    fail "pi-native async entwurf smoke: pi -p exited non-zero"
    return 1
  fi

  # Regression class PM flagged: stale variable name in runEntwurfAsync.
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
  if grep -qE 'Async entwurf spawned|Task ID:' <<< "$raw"; then
    local taskid
    # `head -1` still closes its stdin early, which can send SIGPIPE back
    # to grep under pipefail. Swallow the rc so the assignment survives —
    # the captured string is the only thing we need.
    taskid=$(grep -oE 'Task ID: [a-f0-9]+' <<< "$raw" | head -1 || true)
    ok "pi-native async entwurf spawn (${taskid:-Task ID present})"
    return 0
  fi

  echo "$raw" >&2
  fail "pi-native async entwurf produced neither Task ID nor a recognized error"
  return 1
}

check_bridge() {
  section "pi-tools-bridge (direct MCP + backend visibility)"
  validate_pi_tools_bridge
}

check_native_async() {
  section "pi-native async entwurf spawn"
  validate_pi_native_async_entwurf
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
# Installs the bridge + entwurf orchestration surface (entwurf registry,
# MCP pi-tools-bridge, session-bridge) into a target project and verifies
# end-to-end against both ACP backends. As of the entwurf migration this
# repo owns the orchestration — there is no separate "consuming harness"
# install for the entwurf/registry pieces.
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
  require_cmd node

  # MCP bridge launchers run via `node --experimental-strip-types` (stable in
  # Node 23.6, experimental from 22.6). Anything older lacks the flag, and an
  # ACP session would hit a cryptic "unknown argument" rather than a clear
  # setup-time error. Fail early with an actionable message. package.json
  # engines.node mirrors this floor.
  if ! node -e 'const [M,m]=process.versions.node.split(".").map(Number); process.exit((M>22||(M===22&&m>=6))?0:1)'; then
    echo "[setup] pi-shell-acp requires Node >= 22.6.0 (got $(node -v))" >&2
    echo "[setup] MCP bridge launchers depend on --experimental-strip-types." >&2
    exit 1
  fi

  echo "[setup] repo:    $REPO_DIR"
  echo "[setup] project: $project_dir"
  echo "[setup] scope:   full bridge + entwurf orchestration install"
  echo "[setup] verification: smoke-all + Axis 1 interview gates (pi-tools-bridge, pi-native async, sentinel, session-messaging)"

  (cd "$REPO_DIR" && pnpm install --frozen-lockfile)
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

  smoke_all "$project_dir"

  # Axis 1 interview-prerequisite gates. AGENTS.md §Ingestion Gates names
  # these as required before the Axis 2 agent interview can be re-run.
  # Ported from agent-config pre-Phase-4 (validator bodies) + 7545af8
  # (session-messaging matrix) + pre-Phase-4 sentinel invocation. Default ON
  # here; agent-config (consumer) does not run these anymore.
  section "Axis 1 gate: pi-tools-bridge (direct MCP + backend visibility)"
  validate_pi_tools_bridge

  section "Axis 1 gate: pi-native async entwurf spawn"
  validate_pi_native_async_entwurf

  section "Axis 1 gate: session-messaging 4-case matrix"
  session_messaging_run

  section "Axis 1 gate: sentinel (entwurf 6-cell matrix)"
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
  smoke-entwurf-resume)
    smoke_entwurf_resume "$TARGET_PROJECT_DIR"
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
  check-dep-versions)
    check_dep_versions
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
