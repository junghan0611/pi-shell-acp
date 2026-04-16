# AGENTS.md

## Identity

`pi-shell-acp` is the **ACP bridge provider for pi**.

It should let pi talk to Claude Code through `claude-agent-acp` while keeping the bridge **thin, observable, and restart-safe**.

Current public value:
- `pi-shell-acp/...` provider/model surface
- cross-process ACP session continuity for `pi:<sessionId>`
- Claude Code identity preserved (`~/.claude`, native MCP, native skills)

---

## Scope

This repo owns only the narrow bridge layer:
- provider registration in pi
- ACP subprocess lifecycle
- ACP initialize / resume / load / new session bootstrap
- prompt forwarding
- ACP event -> pi event mapping
- bridge-local cleanup, invalidation, diagnostics

This repo does **not** own:
- pi session UX conventions
- prompt reconstruction from full pi history
- tool ledgers / recovery ledgers
- Claude Code emulation
- broad multi-agent orchestration

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

5. **Shutdown semantics**
   - ordinary process end should preserve persisted mapping
   - explicit invalidation may delete it

6. **Fast failure is better than silent compatibility**
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

## Verification

Run these after meaningful changes:

```bash
npm run typecheck
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
