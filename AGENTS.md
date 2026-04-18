# AGENTS.md

## Identity

`pi-shell-acp` is the **ACP bridge provider for pi**.

It should let pi talk to Claude Code through `claude-agent-acp` while keeping the bridge **thin, observable, and restart-safe**.

Current public value:
- `pi-shell-acp/...` provider/model surface
- cross-process ACP session continuity for `pi:<sessionId>`
- Claude Code identity preserved (`~/.claude`, native skills, Claude Code settings via ACP `settingSources`)
- explicit pi-facing MCP injection into each ACP session via `piShellAcpProvider.mcpServers` — no ambient `~/.mcp.json` scanning, no generic MCP manager behavior

---

## Scope

This repo owns only the narrow bridge layer:
- provider registration in pi
- ACP subprocess lifecycle
- ACP initialize / resume / load / new session bootstrap
- prompt forwarding
- ACP event -> pi event mapping
- explicit pi-facing MCP injection (from `piShellAcpProvider.mcpServers` settings only) into every `newSession` / `resumeSession` / `loadSession` request
- bridge-local cleanup, invalidation, diagnostics

This repo does **not** own:
- pi session UX conventions
- prompt reconstruction from full pi history
- tool ledgers / recovery ledgers
- Claude Code emulation
- broad multi-agent orchestration
- generic MCP discovery / ambient MCP manager behavior (no `~/.mcp.json` scanning, no merging of arbitrary Claude-side configs)
- promotion of pi extension tools to Claude — build a separate MCP adapter for that and register it via `piShellAcpProvider.mcpServers`

If a change makes this repo feel like a second harness, it is probably wrong.

---

## Hard Rules

1. **Surface name is singular**
   - provider id: `pi-shell-acp`
   - model prefix: `pi-shell-acp/...`
   - settings key: `piShellAcpProvider`
   - do not reintroduce legacy aliases

2. **Session continuity boundary**
   - persist only `pi:<sessionId>` mappings
   - never persist `cwd:<cwd>` fallback sessions

3. **Bootstrap order**
   - `resume > load > new`

4. **Keep the bridge thin**
   - no full-history prompt rebuild
   - no tool result ledger
   - no custom Claude behavior emulation
   - no automatic `~/.mcp.json` or ambient MCP discovery — only what `piShellAcpProvider.mcpServers` lists

5. **MCP signature in session compatibility**
   - only the SHA-256 hash of the canonical `mcpServers` shape participates in `bridgeConfigSignature` — no raw canonical JSON is persisted
   - changing the MCP list invalidates the persisted session instead of silently reusing a stale one
   - invalid `mcpServers` input is rejected by `normalizeMcpServers()` with an aggregated `McpServerConfigError` (never silent skip)

6. **Shutdown semantics**
   - ordinary process end should preserve persisted mapping
   - explicit invalidation may delete it

7. **Fast failure is better than silent compatibility**
   - wrong names / wrong settings should fail early

---

## Important Files

- `index.ts`
  - provider registration
  - settings load
  - session shutdown behavior
- `acp-bridge.ts`
  - ACP lifecycle
  - persisted session cache
  - capability detection
  - `resume > load > new`
- `event-mapper.ts`
  - ACP updates -> pi stream events
- `run.sh`
  - install / smoke workflow
- `README.md`
  - public explanation and operator entrypoint

---

## Reference Implementations

When a future agent asks "what is agent-shell?", the short answer is:
- `agent-shell` = an Emacs ACP client with already-mature session orchestration semantics
- `acp.el` = the lower-level Emacs ACP transport layer
- `claude-agent-acp` = the canonical Claude Code ACP server we actually talk to

Primary references:
- https://github.com/xenodium/agent-shell
- https://github.com/xenodium/acp.el
- https://github.com/agentclientprotocol/claude-agent-acp
- https://github.com/agentclientprotocol
- https://github.com/junghan0611/agent-config

Local reference paths on this machine:

```text
/home/junghan/doomemacs/.local/straight/repos/acp.el/acp.el
/home/junghan/doomemacs/.local/straight/repos/agent-shell/agent-shell.el
```

Use them as semantic references for:
- capability detection
- `resume > load > new`
- session bootstrap discipline

Do not import their UI/transcript/session-browser machinery unless there is a very strong reason.

---

## Verification

Run these after meaningful changes:

```bash
npm run typecheck
npm run check-mcp     # pure logic gate, no Claude/ACP subprocess
./run.sh smoke /home/junghan/repos/gh/agent-config
```

For cross-process continuity, verify with the same pi session file:

```bash
cd /home/junghan/repos/gh/agent-config
SESSION_FILE=$(mktemp /tmp/pi-shell-acp-XXXXXX.jsonl)
pi --session "$SESSION_FILE" --provider pi-shell-acp --model claude-3-5-haiku-latest -p 'Remember this exact secret token for later: test-token-123. Reply only READY.'
pi --session "$SESSION_FILE" --provider pi-shell-acp --model claude-3-5-haiku-latest -p 'What was the secret token? Reply with the token only.'
```

Expected: second process returns `test-token-123`.

For fallback boundary, ensure `cwd:` sessions do not create persisted cache records.

---

## Working Style

Prefer surgical changes.

When reviewing a proposed change, ask:
- Does this belong in pi instead?
- Does this belong in Claude Code / claude-agent-acp instead?
- Does this make the bridge more magical than necessary?

If yes, stop and narrow the change.
