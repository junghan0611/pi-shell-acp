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

![pi-shell-acp demo](docs/assets/pi-shell-acp-demo.gif)

Curated ACP-backed models — and the agent on the other side knows it's reached *through* this bridge.

> **Product scope.** `pi-shell-acp` bundles the ACP bridge and the entwurf orchestration surface in one project: entwurf spawn, entwurf-target registry, identity preservation, pi-side MCP adapter (`mcp/pi-tools-bridge`), and the Claude Code ↔ pi session bridge (`mcp/session-bridge`). The earlier "thin bridge, orchestration elsewhere" thesis has been superseded — see AGENTS.md `§Entwurf Orchestration` for the narrative and migration history. External harnesses (e.g. [agent-config](https://github.com/junghan0611/agent-config) as a pi skills/prompts package) can consume this repo without owning any of the surfaces above.

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

## Install

`pi-shell-acp` supports three legitimate install paths. Pick the one that matches the machine you are on.

| Path | Audience | Shape |
|------|----------|-------|
| **A — Consumer**           | end-user of pi (you want to *use* this bridge but not edit it) | `pi install git:…` + `run.sh install .` |
| **B — Developer**          | contributor / first user (you will edit this repo)             | `git clone …` + `pi install ./` + `run.sh install .` |
| **C — Reference consumer** | reading a real wired-up example (skills, prompts, themes on top) | inspect [agent-config](https://github.com/junghan0611/agent-config) |

Both Path A and Path B end in the same runtime state — a valid `<project>/.pi/settings.json` with `piShellAcpProvider.mcpServers` wired. They differ only in who owns the checkout and whether you intend to edit it. See [VERIFY.md §1](./VERIFY.md#1-setup) for the full operator setup walk-through.

### Path A — Consumer install

```bash
# 1. register with pi (pi auto-clones + installs deps into its managed checkout)
pi install git:github.com/junghan0611/pi-shell-acp

# 2. wire the bundled mcpServers into a consumer project
cd /path/to/consumer-project
~/.pi/agent/git/github.com/junghan0611/pi-shell-acp/run.sh install .

# 3. verify model surface
pi --list-models pi-shell-acp

# 4. dual-backend runtime smoke gate
~/.pi/agent/git/github.com/junghan0611/pi-shell-acp/run.sh smoke-all .
```

Notes:
- The checkout at `~/.pi/agent/git/github.com/junghan0611/pi-shell-acp` is pi-managed. Do not edit files there on a consumer machine — `pi update` would overwrite local edits.
- Step 2 is required after `pi install git:…`. `pi install` only adds the package to `~/.pi/agent/settings.json#packages`; per-project `piShellAcpProvider.mcpServers` entries are populated by `./run.sh install .`.

### Path B — Developer install

```bash
# 1. clone + deps
git clone https://github.com/junghan0611/pi-shell-acp ~/repos/gh/pi-shell-acp
cd ~/repos/gh/pi-shell-acp
pnpm install

# 2. register the local checkout with pi
pi install ./

# 3. wire mcpServers into a consumer project
./run.sh install /path/to/consumer-project

# 4. deterministic gates + dual-backend smoke
pnpm typecheck
pnpm check-registration
pnpm check-mcp
pnpm check-backends
pnpm check-models
./run.sh smoke-all /path/to/consumer-project
```

Re-running `./run.sh install` is idempotent. User-authored `mcpServers.<name>` overrides with a different command survive the re-run and are annotated `preserved (user override: …)`. `./run.sh remove /path/to/consumer-project` deletes only entries whose command matches the repo-authored launcher path.

### Path C — Reference consumer (agent-config)

If you want to see what a real production consumer looks like — `pi-shell-acp` wired into a harness with its own skills, prompts, themes, and global `mcpServers` — read [agent-config](https://github.com/junghan0611/agent-config). It treats `pi-shell-acp` as a pi package, owns none of the entwurf orchestration surfaces (those live here), and exercises the same Path A install shape end-to-end.

This repo deliberately does **not** vendor the consumer's settings, skills, or themes. Path C is reading material, not an install step.

## Quick Start

After Install finishes (any path), this is the minimum check from a fresh shell. Replace `$REPO_DIR` with your pi-shell-acp checkout (Path A: `~/.pi/agent/git/github.com/junghan0611/pi-shell-acp`; Path B: wherever you cloned it).

```bash
cd /path/to/consumer-project

# 1. confirm the model surface
pi --list-models pi-shell-acp                                # 6 curated models (claude-sonnet-4-6, claude-opus-4-7, gpt-5.2, gpt-5.4, gpt-5.4-mini, gpt-5.5)

# 2. single-turn Claude smoke
pi --model pi-shell-acp/claude-sonnet-4-6 -p 'reply with ok'

# 3. full dual-backend smoke gate
$REPO_DIR/run.sh smoke-all .
```

If step 3 prints `[smoke-all] Claude + Codex runtime smokes: ok`, the bridge is ready. For an explicit cross-process continuity check with `acpSessionId` diagnostics, run `$REPO_DIR/run.sh verify-resume .`.

## Consumer settings reference

A minimal valid `<project>/.pi/settings.json` produced by `./run.sh install .`:

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

## Authentication

Authentication is handled by Claude Code / claude-agent-acp; pi-shell-acp adds no separate auth layer.

## Non-Goals

This repo should not grow into:
- full-history prompt reconstruction
- backend transcript hydration into pi history
- tool result ledgers
- Claude Code / Codex emulation
- broad multi-agent orchestration *(entwurf spawn is the one intentional exception — narrow, registry-gated, identity-locked; not an open door)*
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
| `pi-extensions/entwurf.ts`            | pi-native entwurf spawn (sync + async modes, Phase 0.5)         |
| `pi-extensions/lib/entwurf-core.ts`   | shared core: registry resolution + Identity Preservation Rule    |
| `pi-extensions/entwurf-control.ts`     | pi entwurf-control server — opens `~/.pi/entwurf-control/<id>.sock`, handles `send`/`get_message`/`clear`/`abort`/`subscribe turn_end` RPC, registers the native `entwurf_send` tool. Ingested from [Armin Ronacher's `agent-stuff`](https://github.com/mitsuhiko/agent-stuff) (Apache 2.0), with `get_summary` dropped to avoid a `pi-ai.complete` dependency. |
| `pi/entwurf-targets.json`             | SSOT allowlist of `(provider, model)` spawn targets              |
| `mcp/pi-tools-bridge/`                 | MCP adapter promoting pi-side tools (`entwurf_send`, `entwurf_peers`, `entwurf`, `entwurf_resume`) to ACP hosts. Depends on `pi-extensions/entwurf-control.ts` being loaded in the *target* pi session to have a socket to talk to. Deliberately narrow — semantic/knowledge search is a skill concern, not a bridge concern. |
| `mcp/session-bridge/`                  | Claude Code ↔ pi Unix-socket session bridge (wire-compatible with pi's entwurf-control) |
| `scripts/session-messaging-smoke.sh`   | 4-case matrix verifying entwurf_send across native/ACP senders × native/ACP targets |

The `delegate` → `entwurf` rename completed at commit `cc6508a` (single commit, no legacy aliases). The `entwurf` name now applies uniformly to MCP tool names, CLI flags, runtime sockets, env vars, file paths, and internal symbols.

## Engraving

The bridge carries a short **engraving** that is surfaced to the ACP-side agent once, during session bootstrap. It is **additive bridge context, not identity replacement** — Claude Code remains Claude Code and Codex remains Codex; the engraving only adds the fact that they are reached *through* `pi-shell-acp`, plus the visible MCP servers in this session.

- Source text lives in [`prompts/engraving.md`](./prompts/engraving.md). Edit at runtime, no rebuild needed.
- Delivery is backend-specific but the source is shared:
  - **Claude** — concatenated into `systemPromptAppend`, delivered via `_meta.systemPrompt.append` at `newSession` / `resumeSession` / `loadSession`.
  - **Codex** — first-prompt `ContentBlock` prepend (Codex `_meta` does not accept the Claude shape).
- A/B experiments: set `PI_SHELL_ACP_ENGRAVING_PATH=/abs/path/to/alt.md`.

Both backends are at parity as of commit `44a0314` (Codex first-prompt delivery) — the engraving reaches each backend through the natural carrier, and the agent on the far side is expected to read it during Layer 0 of [VERIFY.md](./VERIFY.md). See AGENTS.md `## Engraving — Agent Self-Recognition` for the full design rationale.

## Repository Layout

- `index.ts` — provider registration, settings load, shutdown hook
- `acp-bridge.ts` — ACP lifecycle, cache, capability detection, `resume > load > new`
- `event-mapper.ts` — ACP updates -> pi events
- `engraving.ts` + `prompts/engraving.md` — bridge engraving source + render
- `run.sh` — install / operator-facing verification helper (`smoke`, `smoke-codex`, `smoke-all`, `verify-resume`, `sentinel`, `session-messaging`)
- `pi-extensions/` — pi-native extensions: `entwurf.ts` (entwurf spawn), `entwurf-control.ts` (Unix-socket control plane), `lib/entwurf-core.ts` (shared core)
- `mcp/pi-tools-bridge/` — MCP adapter promoting pi-side tools (`entwurf`, `entwurf_resume`, `entwurf_send`, `entwurf_peers`) to ACP hosts
- `mcp/session-bridge/` — Claude Code ↔ pi session bridge (separate MCP server)
- `bench.sh` — **personal benchmark helper, not part of the public install flow.** Korean prompts, direct-vs-bridge timing comparison. Useful only for the maintainer's local quality-vs-latency check; consumers should ignore it.

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

## pi-facing MCP injection

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
- pi-native extension tools are **not** auto-promoted into ACP sessions. The in-repo `mcp/pi-tools-bridge/` is the canonical MCP adapter that promotes the narrow pi-side surface (`entwurf_send`, `entwurf_peers`, `entwurf`, `entwurf_resume`). External adapters remain possible for additional surfaces, but the defaults stay narrow. See AGENTS.md `## Entwurf Orchestration`.
- `./run.sh install <project>` pre-populates `piShellAcpProvider.mcpServers.pi-tools-bridge` and `piShellAcpProvider.mcpServers.session-bridge` pointing at the in-repo `mcp/*/start.sh` launchers, so `pi install git:…pi-shell-acp` + `./run.sh install .` produces a working setup without hand-editing settings.json. Any user-authored override at those names (different `command`/`args`) is preserved — `install` only fills entries it authored. `./run.sh remove <project>` symmetrically deletes only entries that match the repo-authored launcher path; user overrides stay.

After installing into a consumer project, verify:

```bash
cd /path/to/consumer-project
./run.sh setup
```

`setup` now runs the explicit dual-backend operator smoke gate (`smoke-all`) after install/sync, so a setup result is no longer Claude-only by accident.

## Codex backend notes

`backend: "codex"` is a first-class backend with the same engraving + MCP injection contracts as Claude. It is **not** a stripped-down slice.

- launch path: `CODEX_ACP_COMMAND` override first, then `codex-acp` from `PATH`
- pinned runtime/version target: `@zed-industries/codex-acp@0.11.1`
- engraving delivery: first prompt turn `ContentBlock` (Claude uses `_meta.systemPrompt.append`; same source text, backend-specific transport — see `## Engraving` above)
- model inference: if `backend` is omitted and an OpenAI model such as `gpt-5.4` is selected, pi-shell-acp infers `codex` automatically
- `settingSources` / `strictMcpConfig` are Claude-only settings and are ignored on the codex path
- no Claude-specific `_meta.systemPrompt` payload is sent (the Codex `_meta` shape would reject it)

Install / verify:

```bash
pnpm add -g @zed-industries/codex-acp@0.11.1
which codex-acp
pnpm list -g --depth=0 | grep codex-acp
./run.sh smoke-codex /path/to/consumer-project
```

The first-class Codex smoke defaults to `gpt-5.2`, which is a more reliable operator-facing runtime check than `codex-mini-latest` on ChatGPT-backed Codex accounts. (`gpt-5.4` was the previous default but has been observed to be service-unstable in practice.)

## Known limitation: reverse-direction transcript visibility

Forward interoperability is verified:
- pi can create a Codex-backed ACP session
- agent-shell can resume that session and continue it

Reverse direction is only partial today:
- pi can re-attach to the same remote session and continue using it
- but turns added outside pi (for example in agent-shell) are **not** hydrated back into pi's local transcript/history
- later reopening the same session in agent-shell shows those turns again because they remain in the backend-owned session store

This is currently considered a **UX/observability limitation**, not a continuity failure. The bridge intentionally avoids reading backend transcript JSONL stores just to reconstruct pi history.

## Architectural choice: pi stays primary

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
pi --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p 'The codename is owl. Reply with READY only, no explanation.'
pi --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p 'What was the codename I just gave you? Reply in one word only.'
```

Expected:

```text
READY
owl
```

Wording note: this example deliberately uses non-sensitive plaintext (`codename`, `owl`). Avoid `secret token`, `password`, `API key`, or "do not leak" framings — Claude treats those as a safety/exfiltration signal and refuses, which masquerades as a continuity failure. See [VERIFY.md §0A wording guide](./VERIFY.md#verification-prompt-wording--avoid-safety-interpretation-contamination) for the full rule.

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
