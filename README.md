# claude-agent-sdk-pi

> **Fork note (junghan0611):** This is a stability-focused fork of [prateekmedia/claude-agent-sdk-pi](https://github.com/prateekmedia/claude-agent-sdk-pi). Priority is pi-native correctness over feature additions.

This extension registers a custom provider that routes LLM calls through the **Claude Agent SDK** while **pi executes tools** and renders tool results in the TUI.

## Version & Dependencies

| Package | Installed | Latest | Gap | Notes |
|---------|-----------|--------|-----|-------|
| claude-agent-sdk-pi (this fork) | 1.0.16+ | — | — | Stability patches applied |
| @anthropic-ai/claude-agent-sdk | 0.2.32 | 0.2.97 | ~65 versions (2026-02-05 → 04-08) | SDK bridge — upgrade after stability verified |
| @anthropic-ai/sdk | 0.73.0 | 0.86.1 | ~13 versions (2026-02-05 → 04-08) | Anthropic API types |
| @mariozechner/pi-ai | 0.66.1 | — | — | pi core |
| @mariozechner/pi-coding-agent | 0.66.1 | — | — | pi tool schemas (edits[] since 0.66.1) |

> **Upgrade strategy:** Fix pi-native bugs first → verify stability → then upgrade SDK. Mixing both makes root cause isolation impossible.

## Fork Changelog

### 2026-04-09: Stability patch — pi-native correctness

**Problem:** Repeated messages, Edit silent failures, context contamination.

**Root cause analysis (3 bugs):**

1. **Edit arg mapping mismatch** — pi expects `{ path, edits: [{ oldText, newText }] }` but provider sent `{ path, oldText, newText }`. Edit calls silently failed, causing Claude to repeat the same edit proposal.

2. **ToolWatch ledger context contamination** — The ledger (PR #3) re-injected "recovered" tool results into every prompt as text. Combined with `session_id: "prompt"` (no native session), this caused the model to re-process completed work and duplicate messages.

3. **Module re-registration on subagent spawn** — No guard against `registerProvider()` being called twice when subagents reload the module, overwriting the parent’s `streamSimple` with empty state.

**Changes:**

| Fix | File | Lines |
|-----|------|-------|
| Edit args wrapped in `edits[]` array + explicit error on missing args | index.ts | mapToolArgs/edit |
| Grep: pass `ignoreCase`, `literal`, `context` to pi | index.ts | mapToolArgs/grep |
| Find: pass `limit` to pi | index.ts | mapToolArgs/find |
| ToolWatch ledger disabled via `TOOL_WATCH_ENABLED = false` | index.ts | kill switch |
| Module re-registration guard via `Symbol.for()` | index.ts | export default |

**Design principle:** pi manages its own context, sessions, and tool results. This provider should be a thin bridge, not a parallel state machine.

### 2026-04-09: Disable SDK session persistence

- `persistSession: false` — pi manages its own sessions. SDK persistence causes JSONL bloat and state divergence.

### 2026-04-09: Harness-first setup workflow

- Added `run.sh` for local development: setup, auth sync, install, smoke test.

## Highlights

- Claude Agent SDK is used as the LLM backend (Claude Code auth or API key).
- Tool execution is **blocked in Claude Code**; pi executes tools natively.
- Built-in tool calls are mapped to Claude Code tool names.
- Custom tools are exposed to Claude Code via in-process MCP.
- Skills can be appended to Claude Code’s default system prompt (optional).

## Demo

![Demo](screenshot.png)

## Setup

### Harness-first local workflow

For local harness management, use `run.sh` from this repo:

```bash
cd ~/repos/gh/claude-agent-sdk-pi
./run.sh setup ~/repos/gh/agent-config
```

What it does:
- runs `npm install`
- copies `anthropic` OAuth credentials in `~/.pi/agent/auth.json` to the `claude-agent-sdk` alias (if present)
- installs this local repo path into the target project's `.pi/settings.json`
- runs a smoke test with `pi -e <repo> ...`

Other commands:

```bash
./run.sh sync-auth
./run.sh install ~/repos/gh/agent-config
./run.sh smoke ~/repos/gh/agent-config
./run.sh remove ~/repos/gh/agent-config
```

### Standard package install

1) Install the extension globally (npm is the preferred source now):

```
pi install npm:claude-agent-sdk-pi
```

(You can pin a specific version for reproducible installs.)

**Alternative (git):**

```
pi install git:github.com/prateekmedia/claude-agent-sdk-pi
```

See **pi-coding-agent** install docs for other install sources and paths.

2) **Authenticate** (choose one):

- **Claude Code login** (Pro/Max):
  ```bash
  npx @anthropic-ai/claude-code
  ```
  Ensure no API key env vars are set.

- **API key** (API plan):
  ```bash
  export ANTHROPIC_API_KEY=sk-ant-...
  ```

3) Reload pi:

```
/reload
```

## Provider ID

`claude-agent-sdk`

Use `/model` to select:
- `claude-agent-sdk/claude-opus-4-5`
- `claude-agent-sdk/claude-haiku-4-5`

## Tool Behavior

- Claude Code **proposes** tool calls.
- pi **executes** them.
- Tool execution in Claude Code is **denied**.

Built-in tool mapping (Claude Code → pi):

| Claude Code | pi | Args mapped |
|-------------|------|-------------|
| Read | read | `path`, `offset`, `limit` |
| Write | write | `path`, `content` |
| Edit | edit | `path`, `edits: [{ oldText, newText }]` |
| Bash | bash | `command`, `timeout` |
| Grep | grep | `pattern`, `path`, `glob`, `ignoreCase`, `literal`, `context`, `limit` |
| Glob | find | `pattern`, `path`, `limit` |

Claude Code only sees the tools that are active in pi.

### Custom tools

Any extra tools registered in pi are exposed to Claude Code via an in-process MCP server:

- MCP server name: `custom-tools`
- Claude Code tool name format: `mcp__custom-tools__<toolName>`
- Example: `mcp__custom-tools__subagent`

The provider automatically maps these back to the pi tool name (e.g. `subagent`).

## Context loading

1) **Append to system prompt (Default)**
   - Uses **AGENTS.md + skills** from pi and appends to Claude Code’s preset prompt.
   - No extra config needed.

2) **Use Claude Code’s dir (Recommended)**
   - Set `appendSystemPrompt: false` so Claude Code loads its own resources from `.claude/`.
   - By default it loads both user + project settings (`["user","project"]`).
   - If you want to **ignore project-level `.claude/` folders**, set `settingSources: ["user"]`.
   - This provider runs Claude Code in a **tool-denied** mode (pi executes tools), so auto-loading MCP servers from
     `~/.claude.json` is usually just token overhead. By default, the provider passes `--strict-mcp-config` to prevent
     that tool schema dump. Set `strictMcpConfig: false` to opt out.

   **Config (user-only CLAUDE.md/skills + no MCP auto-load):**
   ```json
   {
     "claudeAgentSdkProvider": {
       "appendSystemPrompt": false,
       "settingSources": ["user"],
       "strictMcpConfig": true
     }
   }
   ```

   ```bash
   ln -s ~/.pi/agent/AGENTS.md ~/.claude/CLAUDE.md
   ln -s ~/.pi/agent/skills ~/.claude/skills
   ```
