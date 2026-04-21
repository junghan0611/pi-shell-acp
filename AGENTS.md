# AGENTS.md

## Identity

`pi-shell-acp` is the **ACP bridge provider for pi**.

It should let pi talk to ACP backends such as Claude Code (`claude-agent-acp`) and codex (`codex-acp`) while keeping the bridge **thin, observable, and restart-safe**.

Current public value:
- `pi-shell-acp/...` provider/model surface
- backend selection via `piShellAcpProvider.backend` or model-based inference
- cross-process ACP session continuity for `pi:<sessionId>`
- Claude Code identity preserved (`~/.claude`, native skills, Claude Code settings via ACP `settingSources`) when using the Claude backend
- Codex identity preserved (`~/.codex`, Codex-native session/model UX) when using the codex backend
- explicit pi-facing MCP injection into each ACP session via `piShellAcpProvider.mcpServers` — no ambient backend config scanning, no generic MCP manager behavior

---

## Boundary — Bridge vs Consuming Harness

**Public thesis (English):**

> pi-shell-acp is the thin ACP bridge product. It guarantees backend continuity and explicit MCP injection. Delegate/resume/async orchestration belongs to the consuming harness (currently agent-config), not to this bridge repo.

**운영 원칙 (Korean):**

> pi-shell-acp는 얇은 ACP 브리지다. delegate/resume/async 자체를 소유하지 않는다. 그 위의 MCP 표면과 orchestration은 소비 하네스(agent-config)의 책임이다.

### What this repo is NOT

- ❌ a delegate orchestration layer — `agent-config/pi-extensions/delegate.ts` is the source of truth for delegate / delegate_status / delegate_resume and async task lifecycle.
- ❌ the owner of MCP Phase-2 tools (`delegate_status`, `delegate_resume`, `list_sessions`) — those belong to `agent-config/mcp/pi-tools-bridge`.
- ❌ an async task registry or completion-notification system.
- ❌ a pi extension semantic emulation layer.
- ❌ a second harness. If a change makes this repo feel like a harness, it is probably wrong.

### Install / setup boundary

- `./run.sh setup` (this repo) — **standalone bridge install only**. Builds, wires, and smoke-tests `pi-shell-acp` against a target project. It does not install or build the consuming harness or its MCP adapter.
- `agent-config/run.sh setup` (consuming harness) — full harness install: brings in `pi-shell-acp` as a dependency, then additionally builds `mcp/pi-tools-bridge`, wires `piShellAcpProvider.mcpServers`, and validates the full delegate orchestration surface.

Version and release are tracked independently: the bridge evolves on its own cadence, and the consuming harness pins the bridge version it consumes.

---

## Scope

This repo owns only the narrow bridge layer:
- provider registration in pi
- ACP subprocess lifecycle
- ACP initialize / resume / load / new session bootstrap
- prompt forwarding
- ACP event -> pi event mapping
- explicit pi-facing MCP injection (from `piShellAcpProvider.mcpServers` settings only) into every `newSession` / `resumeSession` / `loadSession` request
- minimal backend adapter selection for ACP launch + backend-specific session metadata
- bridge-local cleanup, invalidation, diagnostics

This repo does **not** own:
- pi session UX conventions
- prompt reconstruction from full pi history
- hydration of backend transcript stores back into pi-local history
- tool ledgers / recovery ledgers
- Claude Code / Codex emulation
- broad multi-agent orchestration
- generic MCP discovery / ambient MCP manager behavior (no `~/.mcp.json` scanning, no merging of arbitrary backend-side configs)
- promotion of pi extension tools to Claude/Codex — build a separate MCP adapter for that and register it via `piShellAcpProvider.mcpServers`

If a change makes this repo feel like a second harness, it is probably wrong.

---

## Hard Rules

1. **Surface name is singular**
   - provider id: `pi-shell-acp`
   - model prefix: `pi-shell-acp/...`
   - settings key: `piShellAcpProvider`
   - do not reintroduce legacy aliases
   - **docs/examples use the qualified form** `--model pi-shell-acp/claude-sonnet-4-6` (prefix routes to this provider — `--provider` becomes redundant and is dropped in examples). Internal smoke helpers that feed `ensureBridgeSession({modelId})` keep bare backend ids (`claude-sonnet-4-6`, `gpt-5.4`) because the bridge library contract is bare.

2. **Session continuity boundary**
   - persist only `pi:<sessionId>` mappings
   - never persist `cwd:<cwd>` fallback sessions

3. **Bootstrap order**
   - `resume > load > new`

4. **Keep the bridge thin**
   - no full-history prompt rebuild
   - no backend transcript ingestion just to reconstruct pi history
   - no tool result ledger
   - no custom backend behavior emulation
   - no automatic ambient MCP discovery — only what `piShellAcpProvider.mcpServers` lists

5. **MCP/backend signature in session compatibility**
   - only the selected backend and the SHA-256 hash of the canonical `mcpServers` shape participate in `bridgeConfigSignature` — no raw canonical JSON is persisted
   - changing the backend or MCP list invalidates the persisted session instead of silently reusing a stale one
   - invalid `mcpServers` input is rejected by `normalizeMcpServers()` with an aggregated `McpServerConfigError` (never silent skip)

6. **Shutdown semantics**
   - ordinary process end should preserve persisted mapping
   - explicit invalidation may delete it

7. **Fast failure is better than silent compatibility**
   - wrong names / wrong settings should fail early

8. **Dual-backend claims require dual-backend runtime verification**
   - if this repo publicly claims support for both Claude and Codex, operator-facing verification must exercise both backends at runtime, not just deterministic adapter checks
   - a single-backend smoke is insufficient evidence for dual-backend readiness
   - do not wait for the user to request symmetry explicitly; infer it from the public claim and add the verification yourself

9. **Operator entrypoints are product surface**
   - `run.sh setup` and `run.sh smoke` are not helper scraps; regressions there are release blockers
   - if setup depends on smoke, smoke regressions are setup regressions
   - any change to bridge bootstrap/backend selection must be checked against the operator entrypoints, not only unit-style checks

---

## External Runtime Dependencies

These are **not** in `node_modules`. They must be installed globally before setup.

### claude-agent-acp (runtime bridge binary)

The actual ACP subprocess that pi-shell-acp spawns is resolved from `PATH` — not from local `node_modules`.

**Pinned version: `0.29.2`**

```bash
pnpm add -g @agentclientprotocol/claude-agent-acp@0.29.2
```

Verify:
```bash
which claude-agent-acp
claude-agent-acp --version 2>/dev/null || true
pnpm list -g --depth=0 | grep claude-agent-acp
```

### Claude Code CLI

The CLI itself is managed separately (via npm, pnpm, or NixOS). `claude --resume` in the terminal may not list `sdk-ts` entrypoint sessions — this is a known CLI UI limitation, not a bridge bug.

**Recommended**: keep CLI version ≥ `2.1.96`. Auto-updates should be disabled in `~/.claude/settings.json`:
```json
{ "autoUpdates": false }
```

### codex-acp

The codex backend runtime is also resolved from `PATH` unless `CODEX_ACP_COMMAND` overrides it.

**Pinned version: `0.11.1`**

```bash
pnpm add -g @zed-industries/codex-acp@0.11.1
```

Verify:
```bash
which codex-acp
codex-acp --help >/dev/null 2>&1 || true
pnpm list -g --depth=0 | grep codex-acp
```

### Why two ACP references exist

| Reference | Version | Purpose |
|-----------|---------|---------|
| pnpm global `claude-agent-acp` | `0.29.2` | Claude runtime bridge binary (spawned by pi) |
| local `node_modules/@agentclientprotocol/claude-agent-acp` | `0.29.2` | Claude SDK import for diagnostics |
| pnpm global `codex-acp` | `0.11.1` | Codex runtime bridge binary (spawned by pi) |
| local `node_modules/@zed-industries/codex-acp` | `0.11.1` | Codex version pin / local reference for repo-managed compatibility |

Pinned versions should stay aligned with what operators actually install. `npm install` keeps local references in sync; pnpm global runtimes must be updated manually.

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
- why agent-shell can feel smoother on resume UX even when pi intentionally does not hydrate backend transcripts

Do not import their UI/transcript/session-browser machinery unless there is a very strong reason.

---

## Verification

Run these after meaningful changes:

```bash
npm run typecheck
npm run check-registration
npm run check-mcp     # pure logic gate, no Claude/ACP subprocess
npm run check-backends
npm run check-claude-sessions -- /home/junghan/repos/gh/agent-config
./run.sh smoke /home/junghan/repos/gh/agent-config
```

### Exit Criteria — backend-related changes

For any change that touches backend selection, launch resolution, session bootstrap, smoke/setup scripts, or public dual-backend claims, the work is **not done** until all of the following are satisfied:

1. deterministic checks pass
   - `npm run typecheck`
   - `npm run check-registration`
   - `npm run check-mcp`
   - `npm run check-backends`
2. operator-facing runtime smoke passes for **Claude**
   - `./run.sh smoke /home/junghan/repos/gh/agent-config`
3. operator-facing runtime smoke passes for **Codex**
   - either a dedicated `./run.sh smoke-codex ...` / `./run.sh smoke-all ...`
   - or an equivalent explicit Codex smoke path with the exact command recorded in the result
4. `setup` must not be left behind
   - if `setup` calls smoke internally, the smoke path it depends on must also be verified
5. docs must match reality
   - README operator commands
   - AGENTS.md invariants / pinned runtime versions / known limitations

If one backend is only covered by deterministic checks but not runtime smoke, do **not** present the repo as fully verified dual-backend support.

For cross-process continuity, verify with the same pi session file:

```bash
cd /home/junghan/repos/gh/agent-config
SESSION_FILE=$(mktemp /tmp/pi-shell-acp-XXXXXX.jsonl)
pi --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p 'Remember this exact secret token for later: test-token-123. Reply only READY.'
pi --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p 'What was the secret token? Reply with the token only.'
```

Expected: second process returns `test-token-123`.

For fallback boundary, ensure `cwd:` sessions do not create persisted cache records.

Known current limitation: when a backend session is continued outside pi (for example in agent-shell), pi may later re-attach to the same remote session successfully but will not replay those external turns into pi-local transcript/history. Treat this as a deliberate thin-bridge boundary unless we find a strictly minimal ACP-native improvement.

Strategic direction: backend choice must not change pi's role as the primary harness. The long-term goal is to expose the same pi-owned MCP/tool surface through either ACP backend without making backend transcript stores the source of truth for pi history.

---

## Working Style

Prefer surgical changes.

When reviewing a proposed change, ask:
- Does this belong in pi instead?
- Does this belong in Claude Code / claude-agent-acp instead?
- Does this make the bridge more magical than necessary?

If yes, stop and narrow the change.
