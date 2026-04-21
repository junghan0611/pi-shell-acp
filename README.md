# pi-shell-acp

> **Status: Work in progress — pre-release.**
> Active development, not yet published. The public surface (provider id, settings keys, persisted bridge signature shape, MCP validation behavior) may change without notice. Use at your own discretion.

Thin ACP bridge provider for pi.

It connects:

```text
pi
  -> pi-shell-acp
    -> claude-agent-acp | codex-acp
      -> Claude Code | Codex
```

The goal is simple:
- keep **pi** as the harness
- keep each ACP backend as itself
- keep this repo as a **small bridge**, not a second harness

## Current Guarantees

- provider/model surface: `pi-shell-acp/...`
- single provider surface, backend selected explicitly or inferred from the selected model
- Claude Code native identity preserved when `backend: "claude"`
  - `~/.claude`
  - native skills / PATH tools
  - Claude Code settings loaded via ACP `settingSources`
- Codex native identity preserved when `backend: "codex"`
  - `~/.codex`
  - codex session store / model catalogue / access modes remain backend-owned
- cross-process ACP session continuity for `pi:<sessionId>`
- persisted bootstrap order: `resume > load > new`
- `cwd:<cwd>` fallback sessions are **not** persisted
- ordinary process shutdown keeps persisted mapping for the next pi process
- explicit pi-facing MCP injection into each ACP session via `piShellAcpProvider.mcpServers` — the bridge never scans ambient backend config files
- **pi session remains the source of truth for pi UX**; backend transcript stores are interoperability side effects, not the canonical history for pi

## Authentication

Authentication is handled by Claude Code / claude-agent-acp; pi-shell-acp adds no separate auth layer.

## Non-Goals

This repo should not grow into:
- full-history prompt reconstruction
- backend transcript hydration into pi history
- tool result ledgers
- Claude Code / Codex emulation
- broad multi-agent orchestration
- a second session model competing with pi

## Design Rules

### 1. One public name
Use only:
- provider id: `pi-shell-acp`
- model prefix: `pi-shell-acp/...`
- settings key: `piShellAcpProvider`

Legacy compatibility was intentionally removed. Wrong names should fail fast.

### 2. Thin bridge
This repo owns:
- provider registration
- ACP subprocess lifecycle
- session bootstrap / invalidation
- prompt forwarding
- ACP event mapping
- bridge-local cleanup and diagnostics

### 3. Session persistence boundary
Persist only `pi:<sessionId>` mappings at:

```text
~/.pi/agent/cache/pi-shell-acp/sessions/<sha256(sessionKey)>.json
```

Persisted data is intentionally minimal:
- session key
- ACP session id
- cwd
- normalized system prompt append
- bridge config signature
- context message signatures
- timestamp / version / provider marker

This is a deliberate architectural choice: `pi-shell-acp` persists only enough to re-attach pi to the same remote ACP session. It does **not** ingest backend transcript files to rebuild pi-local conversation history.

## Repository Layout

- `index.ts` — provider registration, settings load, shutdown hook
- `acp-bridge.ts` — ACP lifecycle, cache, capability detection, `resume > load > new`
- `event-mapper.ts` — ACP updates -> pi events
- `run.sh` — install / operator-facing verification helper (`smoke`, `smoke-codex`, `smoke-all`)
- `bench.sh` — benchmark helper

## Reference Implementations and Upstream Projects

These are the main references behind this repo:

- [xenodium/agent-shell](https://github.com/xenodium/agent-shell)
  - Emacs ACP client UX with mature session orchestration semantics
  - Important idea we borrow: treat ACP sessions as first-class and prefer `resume > load > new`
- [xenodium/acp.el](https://github.com/xenodium/acp.el)
  - Emacs ACP transport library
  - Useful for understanding the minimal client-side ACP request/response surface
- [agentclientprotocol/claude-agent-acp](https://github.com/agentclientprotocol/claude-agent-acp)
  - Canonical ACP server for Claude Code
- [agentclientprotocol](https://github.com/agentclientprotocol)
  - ACP organization / upstream protocol context
- [junghan0611/agent-config](https://github.com/junghan0611/agent-config)
  - Real consumer repo where `pi-shell-acp` is installed and validated via `./run.sh setup`

### Local reference paths used during development

On this machine, the most important local reference files are:

```text
/home/junghan/doomemacs/.local/straight/repos/acp.el/acp.el
/home/junghan/doomemacs/.local/straight/repos/agent-shell/agent-shell.el
```

When working on session bootstrap, capability detection, or resume/load behavior, compare conceptually against those files — but only port the minimal semantics needed here.

## Quick Start

### Local check

```bash
cd ~/repos/gh/pi-shell-acp
npm install
npm run typecheck
npm run check-registration                               # deterministic per-runtime provider registration gate
npm run check-mcp                                        # deterministic MCP validation gate (no Claude/ACP subprocess)
npm run check-backends                                   # deterministic backend launch/meta gate (no ACP subprocess)
npm run check-claude-sessions -- /home/junghan/repos/gh/agent-config  # verify pi persisted sessions are visible to Claude SDK
./run.sh smoke /home/junghan/repos/gh/agent-config       # Claude runtime smoke (backward-compatible default)
./run.sh smoke-codex /home/junghan/repos/gh/agent-config # Codex runtime smoke
./run.sh smoke-all /home/junghan/repos/gh/agent-config   # required dual-backend runtime smoke gate
./run.sh verify-resume /home/junghan/repos/gh/agent-config             # exact pi -> ACP -> Claude continuity check with acpSessionId diagnostics
```

### Use from pi

```bash
cd ~/repos/gh/agent-config
pi --list-models pi-shell-acp
pi --model pi-shell-acp/claude-sonnet-4-6 -p 'ok만 답하세요'
```

## agent-config Integration

`agent-config` should reference this repo in `pi/settings.json` packages and use:

```json
{
  "piShellAcpProvider": {
    "backend": "claude",
    "appendSystemPrompt": false,
    "settingSources": ["user"],
    "strictMcpConfig": false,
    "mcpServers": {}
  }
}
```

### pi-facing MCP injection

`piShellAcpProvider.mcpServers` is the **only** way pi-shell-acp injects MCP servers into the ACP session. It is an explicit allowlist — the bridge forwards exactly what you list here to each ACP session (`newSession` / `resumeSession` / `loadSession`), nothing more, nothing less.

Typical use: you have a single MCP (e.g. a pi-facing `session-bridge`) you want Claude to see inside the pi → ACP flow. Register it here.

Stdio MCP (most common):

```json
{
  "piShellAcpProvider": {
    "mcpServers": {
      "session-bridge": {
        "command": "node",
        "args": ["/abs/path/to/server.js"],
        "env": { "FOO": "bar" }
      }
    }
  }
}
```

HTTP / SSE MCP:

```json
{
  "piShellAcpProvider": {
    "mcpServers": {
      "my-http-mcp": {
        "type": "http",
        "url": "https://example/mcp",
        "headers": { "Authorization": "Bearer …" }
      }
    }
  }
}
```

Notes:
- If `backend` is omitted, pi-shell-acp infers it from the selected model: Anthropic models → `claude`, OpenAI models → `codex`.
- Set `backend` explicitly only when you want to pin the backend regardless of the selected model.
- `mcpServers` from global (`~/.pi/agent/settings.json`) and project (`<cwd>/.pi/settings.json`) are merged by name, project wins on conflict.
- The bridge session signature includes the selected backend and the SHA-256 hash of the canonical `mcpServers` shape — changing either invalidates the persisted session automatically, so the bridge never silently reuses a stale backend/config combination.
- This bridge does **not** read `~/.mcp.json` or any other ambient backend config. If you want a server exposed, list it here.
- Invalid `mcpServers` entries fail fast with a single aggregated error (`McpServerConfigError`) that names every offending server — no silent skips. Validate locally with `npm run check-mcp` before shipping a config.
- pi-native extension tools (`delegate`, `session_search`, `knowledge_search`, …) are **not** auto-promoted. If you want them inside Claude, build a dedicated external MCP adapter and register it here.

After updating `agent-config`, verify:

```bash
cd ~/repos/gh/agent-config
./run.sh setup
```

`setup` now runs the explicit dual-backend operator smoke gate (`smoke-all`) after install/sync, so a setup result is no longer Claude-only by accident.

### Codex backend notes

`backend: "codex"` is intentionally minimal in this slice:
- launch path: `CODEX_ACP_COMMAND` override first, then `codex-acp` from `PATH`
- pinned runtime/version target: `@zed-industries/codex-acp@0.11.1`
- no Claude-specific `_meta` payload is sent
- model selection still flows through the generic ACP session model path when the backend supports it
- `settingSources` / `strictMcpConfig` remain Claude-oriented settings and are ignored by the codex backend path in this slice
- if `backend` is omitted and an OpenAI model such as `gpt-5.4` is selected, pi-shell-acp infers `codex` automatically

Install / verify:

```bash
pnpm add -g @zed-industries/codex-acp@0.11.1
which codex-acp
pnpm list -g --depth=0 | grep codex-acp
./run.sh smoke-codex /home/junghan/repos/gh/agent-config
```

The first-class Codex smoke defaults to `gpt-5.4`, which is a more reliable operator-facing runtime check than `codex-mini-latest` on ChatGPT-backed Codex accounts.

### Known limitation: reverse-direction transcript visibility

Forward interoperability is verified:
- pi can create a Codex-backed ACP session
- agent-shell can resume that session and continue it

Reverse direction is only partial today:
- pi can re-attach to the same remote session and continue using it
- but turns added outside pi (for example in agent-shell) are **not** hydrated back into pi's local transcript/history
- later reopening the same session in agent-shell shows those turns again because they remain in the backend-owned session store

This is currently considered a **UX/observability limitation**, not a continuity failure. The bridge intentionally avoids reading backend transcript JSONL stores just to reconstruct pi history.

### Architectural choice: pi stays primary

This repo deliberately treats **pi session state** as the source of truth for pi UX.

That means:
- ACP backends may keep their own transcript/session stores (`~/.claude/...`, `~/.codex/...`)
- those stores are useful for interoperability with tools like Claude Code or agent-shell
- but pi-shell-acp does **not** read them back just to rebuild pi-local history

This boundary is intentional. It keeps the bridge small and avoids turning backend-owned JSONL/session stores into a second session authority.

The long-term direction is backend-agnostic capability parity: if pi exposes MCP/tool context into ACP sessions, it should do so consistently whether the selected backend is Claude or Codex.

## Cross-Process Continuity Test

```bash
cd ~/repos/gh/agent-config
SESSION_FILE=$(mktemp /tmp/pi-shell-acp-XXXXXX.jsonl)
pi --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p 'Remember this exact secret token for later: test-token-123. Reply only READY.'
pi --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p 'What was the secret token? Reply with the token only.'
```

Expected:

```text
READY
test-token-123
```

For operator-facing identity verification, run:

```bash
cd ~/repos/gh/pi-shell-acp
./run.sh verify-resume /home/junghan/repos/gh/agent-config
```

What to look for:
- first turn logs `[pi-shell-acp] session ...` with `bootstrapPath:"new"` and an `acpSessionId`
- second turn logs `bootstrapPath:"resume"` or `bootstrapPath:"load"`
- the second turn should keep the same `acpSessionId` when Claude-side session continuity is working
- `./run.sh check-claude-sessions ...` output should show that same `acpSessionId` as `VISIBLE`

For a first codex path check from pi configuration, switch the settings block to:

```json
{
  "piShellAcpProvider": {
    "backend": "codex",
    "mcpServers": {}
  }
}
```

and make sure `codex-acp` is resolvable, or set `CODEX_ACP_COMMAND='...'` explicitly.

## Operator-facing smoke commands

Use first-class command paths instead of hidden env overrides:

```bash
./run.sh smoke /home/junghan/repos/gh/agent-config        # Claude runtime smoke (kept for backward compatibility)
./run.sh smoke-claude /home/junghan/repos/gh/agent-config # explicit Claude runtime smoke
./run.sh smoke-codex /home/junghan/repos/gh/agent-config  # explicit Codex runtime smoke (default model: gpt-5.4)
./run.sh smoke-all /home/junghan/repos/gh/agent-config    # required dual-backend runtime verification
```

`smoke-all` is the review/setup quality gate for a repo that publicly claims Claude + Codex support.

## Status

This repo is now suitable for direct work as a dedicated `pi-shell-acp` owner repo.
The next work should focus on careful incremental improvements, not broad reinvention.
