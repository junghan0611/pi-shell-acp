# pi-shell-acp

Thin ACP bridge provider for pi.

It connects:

```text
pi
  -> pi-shell-acp
    -> claude-agent-acp
      -> Claude Code
```

The goal is simple:
- keep **pi** as the harness
- keep **Claude Code** as Claude Code
- keep this repo as a **small bridge**, not a second harness

## Current Guarantees

- provider/model surface: `pi-shell-acp/...`
- Claude Code native identity preserved
  - `~/.claude`
  - native skills / PATH tools
  - Claude Code settings loaded via ACP `settingSources`
- cross-process ACP session continuity for `pi:<sessionId>`
- persisted bootstrap order: `resume > load > new`
- `cwd:<cwd>` fallback sessions are **not** persisted
- ordinary process shutdown keeps persisted mapping for the next pi process
- explicit MCP pass-through via `piShellAcpProvider.mcpServers` — never automatic `~/.mcp.json` scanning

## Use and Authentication

This bridge uses the **user's own Claude Code authentication** (`~/.claude`, OAuth or API key already on the machine).

- No credential proxying, forwarding, or resale.
- No scraping; all traffic goes through the public `@agentclientprotocol/claude-agent-acp` subprocess.
- No bypass of Claude Code's native safety, permission, or rate-limit machinery.
- Tool surface exposed to Claude is entirely derived from explicit settings in this repo and the target project — there is no silent capability injection.

## Non-Goals

This repo should not grow into:
- full-history prompt reconstruction
- tool result ledgers
- Claude Code emulation
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

## Repository Layout

- `index.ts` — provider registration, settings load, shutdown hook
- `acp-bridge.ts` — ACP lifecycle, cache, capability detection, `resume > load > new`
- `event-mapper.ts` — ACP updates -> pi events
- `run.sh` — install / smoke helper
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
./run.sh smoke /home/junghan/repos/gh/agent-config
```

### Use from pi

```bash
cd ~/repos/gh/agent-config
pi --list-models pi-shell-acp
pi --provider pi-shell-acp --model claude-3-5-haiku-latest -p 'ok만 답하세요'
```

## agent-config Integration

`agent-config` should reference this repo in `pi/settings.json` packages and use:

```json
{
  "piShellAcpProvider": {
    "appendSystemPrompt": false,
    "settingSources": ["user"],
    "strictMcpConfig": false,
    "mcpServers": {}
  }
}
```

### MCP pass-through

`mcpServers` is an **explicit allowlist**. The bridge forwards exactly what you list here to every ACP session — nothing more, nothing less.

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
- `mcpServers` from global (`~/.pi/agent/settings.json`) and project (`<cwd>/.pi/settings.json`) are merged by name, project wins on conflict.
- The canonical form of `mcpServers` participates in the bridge session signature — changing it invalidates the persisted session automatically, so Claude never runs with a stale capability set.
- This bridge does **not** read `~/.mcp.json` or any other ambient Claude config. If you want a server exposed, list it here.
- pi-native extension tools (`delegate`, `session_search`, `knowledge_search`, …) are **not** auto-promoted. If you want them inside Claude, build a dedicated external MCP adapter and register it here.

After updating `agent-config`, verify:

```bash
cd ~/repos/gh/agent-config
./run.sh setup
```

## Cross-Process Continuity Test

```bash
cd ~/repos/gh/agent-config
SESSION_FILE=$(mktemp /tmp/pi-shell-acp-XXXXXX.jsonl)
pi --session "$SESSION_FILE" --provider pi-shell-acp --model claude-3-5-haiku-latest -p 'Remember this exact secret token for later: test-token-123. Reply only READY.'
pi --session "$SESSION_FILE" --provider pi-shell-acp --model claude-3-5-haiku-latest -p 'What was the secret token? Reply with the token only.'
```

Expected:

```text
READY
test-token-123
```

## Status

This repo is now suitable for direct work as a dedicated `pi-shell-acp` owner repo.
The next work should focus on careful incremental improvements, not broad reinvention.
