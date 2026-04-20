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
  ./run.sh check-mcp             # local deterministic check of normalizeMcpServers() — no Claude/ACP subprocess
  ./run.sh check-backends        # local deterministic check of backend launch resolution + backend-specific _meta shape
  ./run.sh check-registration    # local deterministic check of per-runtime provider registration semantics
  ./run.sh check-claude-sessions [project-dir]  # compare pi persisted sessions vs Claude SDK session visibility
  ./run.sh verify-resume [project-dir] # exact pi -> ACP -> Claude continuity check with visible acpSessionId diagnostics
  ./run.sh sync-auth             # copy ~/.pi/agent/auth.json anthropic OAuth credentials to pi-shell-acp alias
  ./run.sh install [project-dir] # install this local package into project .pi/settings.json
  ./run.sh remove [project-dir]  # remove pi-shell-acp entries from project .pi/settings.json

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
  local project_dir model
  project_dir=$(normalize_project_dir "$1")
  model=${PI_SHELL_ACP_MODEL:-pi-shell-acp/claude-sonnet-4-6}

  require_cmd pi

  echo "[smoke] project: $project_dir"
  echo "[smoke] repo:    $REPO_DIR"
  echo "[smoke] model:   $model"

  (cd "$project_dir" && pi -e "$REPO_DIR" --list-models pi-shell-acp >/dev/null)
  echo "[smoke] provider models: ok"

  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import { ensureBridgeSession, sendPrompt, setActivePromptHandler, closeBridgeSession, normalizeMcpServers } from './acp-bridge.ts';

const sessionKey = 'run-sh-smoke';
const emptyMcpHash = normalizeMcpServers(undefined).hash;
const session = await ensureBridgeSession({
  sessionKey,
  cwd: process.cwd(),
  modelId: process.env.PI_SHELL_ACP_MODEL_ID || 'claude-sonnet-4-6',
  systemPromptAppend: '간단히 답하세요.',
  settingSources: ['user'],
  strictMcpConfig: false,
  mcpServers: [],
  bridgeConfigSignature: JSON.stringify({ appendSystemPrompt: false, settingSources: ['user'], strictMcpConfig: false, mcpServersHash: emptyMcpHash }),
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

  console.log('[check-backends] 10 assertions ok');
} finally {
  if (prevClaude === undefined) delete process.env.CLAUDE_AGENT_ACP_COMMAND;
  else process.env.CLAUDE_AGENT_ACP_COMMAND = prevClaude;

  if (prevCodex === undefined) delete process.env.CODEX_ACP_COMMAND;
  else process.env.CODEX_ACP_COMMAND = prevCodex;
}
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

ACP_REQUIRED_VERSION="0.29.2"

check_global_acp() {
  local installed
  installed=$(pnpm list -g --depth=0 2>/dev/null | grep -oE '@agentclientprotocol/claude-agent-acp@[0-9.]+' | grep -oE '[0-9.]+$' || true)
  if [[ "$installed" == "$ACP_REQUIRED_VERSION" ]]; then
    echo "[setup] claude-agent-acp global: $installed (ok)"
  elif [[ -n "$installed" ]]; then
    echo "[setup] warning: claude-agent-acp global is $installed, expected $ACP_REQUIRED_VERSION" >&2
    echo "[setup] run: pnpm add -g @agentclientprotocol/claude-agent-acp@$ACP_REQUIRED_VERSION" >&2
  else
    echo "[setup] warning: claude-agent-acp not found in pnpm global" >&2
    echo "[setup] run: pnpm add -g @agentclientprotocol/claude-agent-acp@$ACP_REQUIRED_VERSION" >&2
  fi
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
  check_global_acp
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
  check-mcp)
    check_mcp
    ;;
  check-backends)
    check_backends
    ;;
  check-registration)
    check_registration
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
