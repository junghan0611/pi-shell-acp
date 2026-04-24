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

> **Direction reminder.** `pi-shell-acp` is the reverse direction of [`pi-acp`](https://github.com/svkozak/pi-acp): `pi-acp` lets external ACP clients talk *to* pi; `pi-shell-acp` lets pi talk *to* ACP backends.

The goal is simple:
- keep **pi** as the harness
- keep each ACP backend as itself
- keep this repo as a **small bridge**, not a second harness

> **Product scope.** `pi-shell-acp` bundles the ACP bridge and the entwurf orchestration surface in one project: delegate spawn, delegate-target registry, identity preservation, pi-side MCP adapter (`mcp/pi-tools-bridge`), and the Claude Code ↔ pi session bridge (`mcp/session-bridge`). The earlier "thin bridge, orchestration elsewhere" thesis has been superseded — see AGENTS.md `§Entwurf Orchestration` for the narrative and migration history. External harnesses (e.g. [agent-config](https://github.com/junghan0611/agent-config) as a pi skills/prompts package) can consume this repo without owning any of the surfaces above.

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
- broad multi-agent orchestration *(under revision for the entwurf migration — entwurf spawn is an intentional exception, not a drift)*
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

## Entwurf Orchestration

> Migrated in from agent-config during the entwurf consolidation. This repo now owns the full surface; the original carving is [agent-config `22bd159`](https://github.com/junghan0611/agent-config/commit/22bd159), ingestion is [pi-shell-acp `768baf4`](https://github.com/junghan0611/pi-shell-acp/commit/768baf4) plus the `da97fa9`/`060c412`/`9269771`/`6939e7e` stabilization round. See AGENTS.md `§Entwurf Orchestration` for the full narrative, schema, and release baseline.

**Surfaces in this repo.**

| Path                                   | Purpose                                                          |
|----------------------------------------|------------------------------------------------------------------|
| `pi-extensions/delegate.ts`            | pi-native delegate spawn (sync + async modes, Phase 0.5)         |
| `pi-extensions/lib/delegate-core.ts`   | shared core: registry resolution + Identity Preservation Rule    |
| `pi-extensions/session-control.ts`     | pi session-control server — opens `~/.pi/session-control/<id>.sock`, handles `send`/`get_message`/`clear`/`abort`/`subscribe turn_end` RPC, registers the native `send_to_session` tool. Ingested from [Armin Ronacher's `agent-stuff`](https://github.com/mitsuhiko/agent-stuff) (Apache 2.0), with `get_summary` dropped to avoid a `pi-ai.complete` dependency. |
| `pi/delegate-targets.json`             | SSOT allowlist of `(provider, model)` spawn targets              |
| `mcp/pi-tools-bridge/`                 | MCP adapter promoting pi-side tools (`send_to_session`, `list_sessions`, `delegate`, `delegate_resume`) to ACP hosts. Depends on `pi-extensions/session-control.ts` being loaded in the *target* pi session to have a socket to talk to. Deliberately narrow — semantic/knowledge search is a skill concern, not a bridge concern. |
| `mcp/session-bridge/`                  | Claude Code ↔ pi Unix-socket session bridge (wire-compatible with pi's session-control) |
| `scripts/session-messaging-smoke.sh`   | 4-case matrix verifying send_to_session across native/ACP senders × native/ACP targets |

The identifier `delegate` is the current in-repo name. A single rename commit to `entwurf` is pending as the final cosmetic step of the migration — see AGENTS.md `§Entwurf Orchestration § Migration Plan (step 6)`.

Related: see `## Engraving — Agent Self-Recognition` in AGENTS.md for how the delegate tool surfaces in the ACP session identity.

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

## Quick Start

### Local check

```bash
cd ~/repos/gh/pi-shell-acp
npm install
npm run typecheck
npm run check-registration                               # deterministic per-runtime provider registration gate
npm run check-mcp                                        # deterministic MCP validation gate (no Claude/ACP subprocess)
npm run check-backends                                   # deterministic backend launch/meta gate (no ACP subprocess)
npm run check-claude-sessions -- /path/to/consumer-project  # verify pi persisted sessions are visible to Claude SDK
./run.sh smoke /path/to/consumer-project       # Claude runtime smoke (backward-compatible default)
./run.sh smoke-codex /path/to/consumer-project # Codex runtime smoke
./run.sh smoke-all /path/to/consumer-project   # required dual-backend runtime smoke gate
./run.sh verify-resume /path/to/consumer-project             # exact pi -> ACP -> Claude continuity check with acpSessionId diagnostics
```

### Use from pi

```bash
cd /path/to/consumer-project
pi --list-models pi-shell-acp
pi --model pi-shell-acp/claude-sonnet-4-6 -p 'ok만 답하세요'
```

## Consumer example: agent-config

This section shows how an external harness can consume `pi-shell-acp` as a pi package. [agent-config](https://github.com/junghan0611/agent-config) is the reference consumer — it wires `pi-shell-acp` into its own `pi/settings.json`, uses the provider surface this repo exposes, and adds its own skills / prompts / themes on top without owning any of the entwurf orchestration pieces (those live here).

Typical consumer settings:

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
- pi-native extension tools are **not** auto-promoted into ACP sessions. The in-repo `mcp/pi-tools-bridge/` is the canonical MCP adapter that promotes the narrow pi-side surface (`send_to_session`, `list_sessions`, `delegate`, `delegate_resume`). External adapters remain possible for additional surfaces, but the defaults stay narrow. See AGENTS.md `## Entwurf Orchestration`.
- `./run.sh install <project>` pre-populates `piShellAcpProvider.mcpServers.pi-tools-bridge` and `piShellAcpProvider.mcpServers.session-bridge` pointing at the in-repo `mcp/*/start.sh` launchers, so `pi install git:…pi-shell-acp` + `./run.sh install .` produces a working setup without hand-editing settings.json. Any user-authored override at those names (different `command`/`args`) is preserved — `install` only fills entries it authored. `./run.sh remove <project>` symmetrically deletes only entries that match the repo-authored launcher path; user overrides stay.

After installing into a consumer project, verify:

```bash
cd /path/to/consumer-project
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
- if `backend` is omitted and an OpenAI model such as `gpt-5.2` is selected, pi-shell-acp infers `codex` automatically

Install / verify:

```bash
pnpm add -g @zed-industries/codex-acp@0.11.1
which codex-acp
pnpm list -g --depth=0 | grep codex-acp
./run.sh smoke-codex /path/to/consumer-project
```

The first-class Codex smoke defaults to `gpt-5.2`, which is a more reliable operator-facing runtime check than `codex-mini-latest` on ChatGPT-backed Codex accounts. (`gpt-5.4` was the previous default but has been observed to be service-unstable in practice.)

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
cd /path/to/consumer-project
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
cd /path/to/pi-shell-acp
./run.sh verify-resume /path/to/consumer-project
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
./run.sh smoke /path/to/consumer-project        # Claude runtime smoke (kept for backward compatibility)
./run.sh smoke-claude /path/to/consumer-project # explicit Claude runtime smoke
./run.sh smoke-codex /path/to/consumer-project  # explicit Codex runtime smoke (default model: gpt-5.2)
./run.sh smoke-all /path/to/consumer-project    # required dual-backend runtime verification
```

`smoke-all` is the review/setup quality gate for a repo that publicly claims Claude + Codex support.

## Status

This repo is now suitable for direct work as a dedicated `pi-shell-acp` owner repo.
The next work should focus on careful incremental improvements, not broad reinvention.
