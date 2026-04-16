#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR_DEFAULT=$(pwd)
TARGET_PROJECT_DIR=${2:-$PROJECT_DIR_DEFAULT}
PACKAGE_NAME="pi-shell-acp"
PROVIDER_ID="pi-shell-acp"

usage() {
  cat <<'EOF'
Usage:
  ./run.sh setup [project-dir]   # npm install + sync auth alias + install this local package into project .pi/settings.json
  ./run.sh smoke [project-dir]   # smoke test provider/model loading and a simple prompt
  ./run.sh sync-auth             # copy ~/.pi/agent/auth.json anthropic OAuth credentials to pi-shell-acp alias
  ./run.sh install [project-dir] # install this local package into project .pi/settings.json
  ./run.sh remove [project-dir]  # remove pi-shell-acp / legacy claude-agent-sdk-pi entries from project .pi/settings.json

Notes:
  - project-dir defaults to current directory
  - Claude Code login should already exist (e.g. ~/.claude.json)
  - API key is optional; this bridge is intended to work with Claude Code auth
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

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
    if isinstance(source, str) and ("claude-agent-sdk-pi" in source or "pi-shell-acp" in source) and source != repo_dir:
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
    if isinstance(source, str) and ("claude-agent-sdk-pi" in source or "pi-shell-acp" in source):
        removed += 1
        continue
    filtered.append(item)

data["packages"] = filtered
settings_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"remove: removed {removed} entries from {settings_path}")
PY
}

smoke_test() {
  local project_dir model
  project_dir=$(normalize_project_dir "$1")
  model=${PI_SHELL_ACP_MODEL:-${PI_CLAUDE_AGENT_SDK_MODEL:-pi-shell-acp/claude-sonnet-4-6}}

  require_cmd pi

  echo "[smoke] project: $project_dir"
  echo "[smoke] repo:    $REPO_DIR"
  echo "[smoke] model:   $model"

  (cd "$project_dir" && pi -e "$REPO_DIR" --list-models pi-shell-acp >/dev/null)
  echo "[smoke] provider models: ok"

  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import { ensureBridgeSession, sendPrompt, setActivePromptHandler, closeBridgeSession } from './acp-bridge.ts';

const sessionKey = 'run-sh-smoke';
const session = await ensureBridgeSession({
  sessionKey,
  cwd: process.cwd(),
  modelId: process.env.PI_SHELL_ACP_MODEL_ID || process.env.PI_CLAUDE_AGENT_SDK_MODEL_ID || 'claude-sonnet-4-6',
  systemPromptAppend: '간단히 답하세요.',
  settingSources: ['user'],
  strictMcpConfig: false,
  bridgeConfigSignature: JSON.stringify({ appendSystemPrompt: false, settingSources: ['user'], strictMcpConfig: false }),
  contextMessageSignatures: ['smoke:user:ok만 답하세요.'],
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
console.log(`[smoke] bridge response: ${text.trim()}`);
EOF
  )
  echo "[smoke] bridge prompt: ok"
}

setup_all() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")

  require_cmd npm
  require_cmd python3
  require_cmd pi

  echo "[setup] repo:    $REPO_DIR"
  echo "[setup] project: $project_dir"

  (cd "$REPO_DIR" && npm install)
  sync_auth
  install_local_package "$project_dir"

  if [[ -f "$HOME/.claude.json" ]]; then
    echo "[setup] ~/.claude.json detected"
  else
    echo "[setup] warning: ~/.claude.json not found. Run 'npx @anthropic-ai/claude-code' first if needed." >&2
  fi

  smoke_test "$project_dir"
}

cmd=${1:-}
case "$cmd" in
  setup)
    setup_all "$TARGET_PROJECT_DIR"
    ;;
  smoke)
    smoke_test "$TARGET_PROJECT_DIR"
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
