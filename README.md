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
  - native MCP
  - native skills / PATH tools
- cross-process ACP session continuity for `pi:<sessionId>`
- persisted bootstrap order: `resume > load > new`
- `cwd:<cwd>` fallback sessions are **not** persisted
- ordinary process shutdown keeps persisted mapping for the next pi process

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
    "strictMcpConfig": false
  }
}
```

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
