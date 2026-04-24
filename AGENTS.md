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

## Engraving — Agent Self-Recognition

> Ref: [[denote:20260423T141759][힣맨 프롤로그 2탄 — 힣의 드라이버: 단련된 한 자루의 각인]].

The bridge carries a short **engraving** that is surfaced to the ACP-side agent once, during session bootstrap. It is not an operating contract or a system-prompt append. It is a short invocation — the cue that turns "I am Claude Code holding a Swiss Army knife" into "I am one of 힣's군단, and the tool in my hand opens into a harness via MCP."

### Body

```text
You currently hold one tool forged in 힣's 대장간.
It appears small. It is not.
Read the available MCP servers and skills to see what this tool opens.
When entwurf is invoked, you do not spawn workers — you summon siblings
who hold the same tool.
```

Six lines. No operating contract, no 500-token preamble. Two statements: *read the tool you already hold*, and *entwurf summons siblings, not workers*.

### How it hooks into ACP

The engraving is emitted at ACP `initialize` time, after the capability exchange completes. At that point the bridge already knows:

1. which MCP servers were injected via `piShellAcpProvider.mcpServers`
2. which host-side skills / PATH tools the backend sees (Claude Code surfaces `~/.claude/skills/…` via native skill loading; Codex surfaces its own tool set)

Those two lists are dynamically interpolated into the engraving body before it is surfaced, so the text the agent reads reflects *what is actually connected*, not a static claim.

This connects directly to Layer 0 of [VERIFY.md](./VERIFY.md): the real answer to "what environment are you in, what tools do you have" is not agent introspection guesswork — it is *did you read the engraving you were given*. Answering Layer 0 without having seen the engraving is a bridge boot path bug, not an agent hallucination.

### Why it lives in this repo (not in agent-config)

The engraving is the surface where *this bridge's identity* is declared to the agent session it owns. It references `entwurf`, which is migrating into this repo (see `## Entwurf Orchestration` below). Putting the engraving anywhere but here would mean the bridge announces an identity authored by another repo — incoherent.

---

## Entwurf Orchestration — [INCOMING: from agent-config]

> **Migration marker (mirror).** The delegate/resume orchestration, target registry, identity preservation rule, and cross-session bridges currently live in [agent-config](https://github.com/junghan0611/agent-config) and are slated to migrate **into this repo**. The `delegate` → `entwurf` rename is performed on this side in a single commit after ingestion.
>
> **Grep key: `Entwurf Orchestration`.** A mirror section with the same name exists in agent-config as `[MIGRATION: → pi-shell-acp]` — carved out in agent-config commit [`22bd159`](https://github.com/junghan0611/agent-config/commit/22bd159). When both markers disappear, migration is complete.
>
> **Ref:** [[denote:20260423T141759][힣맨 프롤로그 2탄 — 힣의 드라이버]]. This migration is the technical expression of that narrative: pi-shell-acp becomes the forged driver — ACP runtime manifest + MCP bridge + entwurf button — not a thin passthrough.

### Migration Plan

**Why this repo is the new home.** The earlier boundary ("thin bridge; orchestration stays in the consuming harness") treated pi-shell-acp as a passthrough. Experience since then showed the delegate surface, the target registry, identity preservation, and the MCP adapters that promote pi-side tools to ACP hosts all cluster around the same ACP session lifecycle this bridge already owns. Splitting them across two repos produced seam churn without a real boundary gain. The new direction consolidates them here — one project, new home.

**Ordering (mirrored with agent-config).**
1. agent-config carves the migration-marked section (`22bd159`, done).
2. pi-shell-acp lands this `[INCOMING]` mirror section (this commit).
3. Phase 0.5 (sync/async mode contract) implements and verifies in agent-config.
4. `send_to_session` 3-way smoke (native↔native, native↔ACP, ACP↔ACP) verifies in agent-config.
5. The carved content — policy, schema, `delegate-core`, `pi-tools-bridge`, `session-bridge` — moves here verbatim.
6. A single pi-shell-acp commit performs `delegate` → `entwurf` rename across code and docs.
7. agent-config drops the migration marker and keeps a consumer-side pointer to where the logic lives.

**Naming contract — deliberate asymmetry.**
- This repo (new owner): `entwurf` is the canonical term from this section forward. `delegate` appears only as a legacy alias when referencing agent-config's pre-migration code.
- agent-config (current code owner): `delegate` remains canonical until the rename commit (step 6). Renaming there before the code moves would break grep and desync docs from code.

This asymmetry is load-bearing. Do not "fix" it prematurely.

### Incoming Artifacts

Six surfaces move into this repo. Landing positions are provisional and will be finalized at ingestion time.

| Source                                 | Destination (pi-shell-acp, planned)           | Purpose                                                          |
|----------------------------------------|-----------------------------------------------|------------------------------------------------------------------|
| `pi-extensions/delegate.ts` (agent-config) | `entwurf/spawn.ts` (or similar)           | pi-native spawn entry                                            |
| `pi-extensions/lib/delegate-core.ts` (agent-config) | `entwurf/core.ts`                | shared core: registry resolution + identity lock                 |
| `pi/delegate-targets.json` (agent-config) | `entwurf/targets.json`                     | SSOT allowlist of `(provider, model)` pairs                      |
| `mcp/pi-tools-bridge/` (agent-config)  | `mcp/pi-tools-bridge/`                        | MCP adapter exposing entwurf (delegate/delegate_resume) + session-control (send_to_session/list_sessions) to ACP hosts |
| `mcp/session-bridge/` (agent-config)   | `mcp/session-bridge/`                         | Claude Code ↔ pi Unix-socket session bridge                      |
| `extensions/control.ts` (Armin agent-stuff, Apache 2.0) | `pi-extensions/session-control.ts` | pi session-control server (Unix socket, RPC protocol, `send_to_session` native tool). Closes the hidden runtime dependency that previously made pi-tools-bridge require a private consumer repo to work. |

**"One project" principle — preserved, not split.** agent-config's AGENTS.md Entwurf Orchestration section states: *"After migration both live together inside pi-shell-acp; the 'one project' principle is preserved, just with a new home."* This repo honors that contract. `pi-extensions`-equivalent surface and `mcp/*` adapters live side-by-side here; they are not to be split into sibling repos later. The session-control extension is the public counterpart of this principle — pi-shell-acp owns the server side of `send_to_session`, not just the bridge-side caller.

### Runtime compatibility — aligned to pi 0.70.0

This repo pins exact pi library versions that match the pi runtime users actually install. pi is a fast-moving tool; users update immediately. Carrying an old library pin into a public release invites drift from day one.

| Package | pi-shell-acp where | Rationale |
|---------|---------------------|-----------|
| `@mariozechner/pi-coding-agent` | peerDep + devDep `0.70.0` | matches current pi runtime; exact pin for release reproducibility |
| `@mariozechner/pi-ai` | peerDep + devDep `0.70.0` | `StringEnum` / `TextContent` used by session-control.ts |
| `@mariozechner/pi-tui` | peerDep + devDep `0.70.0` | `Box/Container/Markdown/Spacer/Text` used by session-control.ts tool-result renderer (message-received / clear) |
| `@sinclair/typebox` | runtime dep `^0.34.0` | `Type.*` used by `pi-extensions/delegate.ts` + `pi-extensions/session-control.ts`; moved to runtime deps so `pi install git:…` (which runs `npm install --omit=dev`) still resolves it |

**0.70.0 adaptation log** (landed in commit `da97fa9`, authored as "Commit A" in the stabilization round):

- `AgentToolResult<T>` no longer carries `isError`. 0.70.0 docstring: *"Throw on failure instead of encoding errors in content"*. All six `isError: ...` usages in `pi-extensions/delegate.ts` removed; error paths now distinguished via `content` text + structured `details` only.
- Tool `execute` signature gained a 5th required param `ctx: ExtensionContext`. Three handlers updated (`delegate`, `delegate_status`, `delegate_resume`).
- `AgentToolResult<T>.details: T` is required. Two partial-update `onUpdate` callbacks fixed with `details: {}`.
- Each execute annotated with explicit return type `Promise<AgentToolResult<unknown>>` — locks the runtime contract at the function boundary.
- TS2589 "Type instantiation excessively deep" on delegate tool registration (0.70.0 `registerTool` couples typebox `Static<TParams>` with `TDetails` inference; delegate's 6-Optional + nested-Union params exceeded recursion depth) worked around with a localized `registerTool` cast — execute bodies still typed.

A brief 0.67.2 pin lived in commit `768baf4` (step 5 verbatim ingestion) as an intermediate step; `da97fa9` replaced it. The history is preserved but the current state is 0.70.0-aligned.

### Typecheck boundary

`tsconfig.json` excludes `node_modules`, `mcp/`, and `pi-extensions/session-control.ts` from the root typecheck.

- `mcp/*` is plain source under the single root package (no sub-package, no `tsconfig.json`, no `dist/` — that layout was removed in `035254b`). At runtime each bridge launcher (`mcp/*/start.sh`) runs `node --experimental-strip-types` on `src/*.ts` directly. `mcp/` is excluded from root tsc because `check-models` needs tsc to emit a verification build, and pulling bridge sources in would require `allowImportingTsExtensions: true` which forces `noEmit: true`. Bridge code is instead covered by behavioral tests (`mcp/pi-tools-bridge/test.sh`) plus a parse-time smoke at every ACP session boot. Acceptable tradeoff for a small, isolated surface.
- `pi-extensions/delegate.ts` + `pi-extensions/lib/*` **are covered** by the root typecheck (as of `da97fa9`). Previously excluded because the ingested code had pre-existing type drift against pi library types; the 0.70.0 adaptation closed that gap.
- `pi-extensions/session-control.ts` is **excluded** from the root typecheck. The ingested Armin `control.ts` uses `pi-coding-agent` / `pi-ai` / `@sinclair/typebox` surfaces (`StringEnum` return type, `pi.on("session_switch")` / `session_fork`, `AgentToolResult.isError`, etc.) that no longer line up with the 0.70.0 declared types on our end. The runtime behaviour still works — pi loads the extension via strip-types at session start — so we treat it the same way as `mcp/*`: runtime-verified, outside the root typecheck. Pull it back in when Armin's type shape and our pin converge, not by editing the ingested source to chase our local tsc opinion.

### Phase 0.5 — sync/async mode contract (completed upstream at agent-config `e5aa5a1`)

Phase 0.5 landed in [agent-config `e5aa5a1`](https://github.com/junghan0611/agent-config/commit/e5aa5a1) and is part of the ingested surface.

**What it did.** `delegate_resume` previously had cross-surface asymmetry: pi-native was async (followUp delivery), MCP bridge was already sync. `e5aa5a1` added `mode: "sync" | "async"` (default `"sync"`) on the pi-native surface, wiring the sync branch to the same `runDelegateResumeSync` the MCP bridge already called. Async branch is byte-identical to the pre-commit detached-followUp path.

**Evidence carried into ingestion.**
- MCP bridge test.sh: 15/15 baseline at `e5aa5a1`; now 13/13 after the narrow-scope cleanup in `035254b` (two E2E assertions tied to the removed `session_search`/`knowledge_search` tools went with them)
- sentinel cell 1 (native → `openai-codex/gpt-5.2`): sync inline return, identity preserved, model=gpt-5.2. Artifact `/tmp/sentinel-phase05-cell1.json`.
- ad-hoc async smoke: Resume ID 7d7c5b84 spawned detached (PID 54061), followUp semantics unchanged.
- callsite audit: only LLM-driven tool invocations consume `delegate_resume` — no internal callers break from the default flip.

**After ingestion.** `mode: "sync" | "async"` is on `delegate_resume` as ingested (to become `entwurf_resume` in step 6). No further Phase 0.5 work pending.

### Send-is-throw Principle (cross-session messaging)

Incoming with the artifacts above, already established upstream:

> Send is throw, not wait. An agent sends and moves on. If a reply is needed, the message itself asks the recipient to send back. If the work is truly important, use `entwurf` (own the outcome) instead of a message (notify and move on).

Practical consequence at ingestion: `send_to_session` and `list_sessions` move here; `wait_until` is intentionally not bridged to MCP. Blocking is a design smell in this model.

### Ingestion Gates

"Migration complete" is not a file-move event. Content moving into this repo must pass **both verification axes** (see `## Verification § Two axes`) at the new home before the migration markers are removed.

**Axis 1 — Protocol smoke (inherited from agent-config).** The smoke paths that validated entwurf in agent-config must pass against the same surfaces hosted here.

- `mcp/pi-tools-bridge/test.sh` — protocol + negative-path tests (15/15 baseline at `e5aa5a1`; 13/13 after narrow-scope cleanup at `035254b`)
- entwurf spawn sentinel cell (sync + async variants) — the same sentinel artifact shape agent-config used at `e5aa5a1` (`/tmp/sentinel-phase05-cell1.json`)
- `scripts/session-messaging-smoke.sh` — **4-case matrix**: native→native (baseline), native→ACP, MCP→native, MCP→ACP. Originally framed as a "3-way" matrix; the actual smoke in agent-config `7545af8` includes the native↔native baseline as a fourth case to catch regressions in the non-ACP path.

These are deterministic gates. They fail fast and are cheap to re-run.

**Axis 2 — Agent interview (local to this repo's VERIFY.md).** A real `pi-shell-acp/<model>` session must answer VERIFY.md §1A Layer 0–4 with the new in-repo entwurf surface, not the agent-config one.

- Layer 0 — does the session read the engraving (`## Engraving`) and recognize entwurf as a first-class tool in this repo, not a referenced one?
- Layer 2 — does pi-facing MCP (now including `pi-tools-bridge` hosted here) actually reach the turn? Can the agent see and call the four exposed tools (entwurf's `delegate`/`delegate_resume` and session-control's `send_to_session`/`list_sessions`)?
- Layer 3 — does identity preservation (the Resume Lock) hold when the entwurf resume is invoked from an in-session agent, not from a command-line `pi -p`?

Passing Axis 1 alone is not enough. Pre-Phase-0.5 we saw a green protocol smoke next to a broken interview; that failure mode is specifically what the two-axis rule exists to catch.

**Evidence requirement.** Each ingestion commit records Axis 1 sentinel artifacts + Axis 2 interview transcript summary in the commit body, the same way agent-config `e5aa5a1` recorded its smoke evidence. "It worked on my machine" is not evidence; artifact paths and token echoes are.

### Release Baseline (post-stabilization)

The stabilization round between step 5 (ingestion) and step 6 (rename) locked the following runtime state — the release target for the first public `pi-shell-acp` cut that bundles entwurf orchestration:

| Surface | State |
|---------|-------|
| pi runtime | `0.70.0` |
| `@mariozechner/pi-ai` | exact `0.70.0` |
| `@mariozechner/pi-coding-agent` | exact `0.70.0` |
| `pi-extensions/` | covered by root typecheck |
| Curated model surface | `claude-sonnet-4-6`, `claude-opus-4-7`, `gpt-5.2`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.5` |
| Codex metadata source | `getModels("openai-codex")` (NOT `"openai"`) |
| `gpt-5.5` context window | `400,000` (openai-codex source; openai source claim of `1,050,000` is not served by codex-acp) |
| Claude context cap | `200,000` default; `PI_SHELL_ACP_CLAUDE_CONTEXT=1000000` opt-in |
| Delegate target registry | 10 entries — 2 Claude, 4 native Codex, 4 ACP Codex (`explicitOnly`) |

Stabilization commits (read in order for the release story):

| SHA | Title | Purpose |
|-----|-------|---------|
| `768baf4` | Step 5 verbatim ingestion | Move the 5 surfaces + smoke script from agent-config. Temporary `0.67.2` pin + `pi-extensions` typecheck exclude as intermediate step. |
| `da97fa9` | Commit A — 0.70.0 align + delegate.ts API adapt | Exact `0.70.0` pin on pi libs. Remove `isError` (6 sites). Add `ctx` to 3 execute signatures. Add `details` to 2 onUpdate callbacks. Explicit `Promise<AgentToolResult<unknown>>` returns. TS2589 workaround. `pi-extensions` back in typecheck. |
| `060c412` | Commit B — curate model surface + fix codex metadata source | Replace wholesale `getModels("anthropic") + getModels("openai")` with curated allowlist against `getModels("openai-codex")`. Fix `gpt-5.5` ctx regression (1.05M → 400K). Rewrite `check-models` with exact allowlist + forbidden-list + codex context gates. |
| `9269771` | Commit C — gpt-5.5 in delegate registry | Add `openai-codex/gpt-5.5` (native) + `pi-shell-acp/gpt-5.5` (explicitOnly). Cost warning in `$notes`. Update `$comment` to point at pi-shell-acp AGENTS.md (was agent-config pre-migration). |

Axis 1 gates at release baseline (all pass against the state above, post Phase 5 wiring in `a70500a`):

```text
pnpm run typecheck                   clean (root; mcp/* excluded — see § Typecheck boundary)
./run.sh check-registration          7/7
./run.sh check-mcp                   15/15
./run.sh check-models                3/3 (curated + cap + override)
./run.sh check-backends              12/12
./run.sh check-compaction-handoff    pass
./run.sh smoke-all                   claude + codex bridge prompt ok
./run.sh check-bridge                pi-tools-bridge direct MCP (4 tools — narrow scope, see src/index.ts header) + test.sh (13/13) + in-ACP visibility+invocation for claude and codex
./run.sh check-native-async          pi-native async delegate spawn (Task ID captured)
./run.sh session-messaging           4/4  (native→ACP, mcp→native, mcp→ACP, native→native)
./run.sh sentinel                    6/6  (parent ∈ {native, acp-claude, acp-codex} × target models)
pi -e . --list-models pi-shell-acp   → 6 curated models, gpt-5.5 at 400K
```

All of the above are now wired into `./run.sh setup`, which fails loudly on any single gate regression. `npm run` usages in this section were rewritten to `./run.sh` / `pnpm run` after the pnpm migration in `3bf5f8f`. The last four gates — `check-bridge`, `check-native-async`, `session-messaging`, `sentinel` — moved into this repo's `run.sh` in Phase 5 (`a70500a`); agent-config deleted its copies of the same logic in Phase 4 (`05d525b`).

Most recent green run: 2026-04-24, all gates pass on fresh install (clean `node_modules` + `dist`), artifacts:

```text
/tmp/pi-shell-acp-setup-v2.log
/tmp/session-messaging-smoke-20260424-110103.json
/tmp/sentinel-20260424-110111.json
```

Axis 2 — VERIFY.md §1A Layer 0–4 interview — is owned by the agent inside a `pi-shell-acp/<model>` session, not by this Claude Code session. With Axis 1 confirmed green end-to-end, the Axis 2 interview is now unblocked (step 6 rename gate precondition).

### Superseded Boundary

The previous `## Boundary — Bridge vs Consuming Harness` section (below, marked `[SUPERSEDED]`) is the pre-entwurf thesis. It is kept in place during the transition window as historical reference — do not delete it until migration step 7 completes.

---

## Historical Boundary — Pre-Entwurf Thesis [SUPERSEDED]

> **This section is historical context only, not the current ownership model.** It documents a boundary that no longer applies. For current ownership, read `## Entwurf Orchestration` and `## Scope` (Layer A / Layer B). The quotes below are frozen snapshots of the old thesis kept for migration trail — do not treat them as current fact. Specific path references in the old boundary (`agent-config/pi-extensions/...`, `agent-config/mcp/pi-tools-bridge`, etc.) no longer match reality; those surfaces now live in this repo.

**Frozen thesis — English (pre-entwurf):**

> pi-shell-acp is the thin ACP bridge product. It guarantees backend continuity and explicit MCP injection. Delegate/resume/async orchestration belongs to the consuming harness (currently agent-config), not to this bridge repo.

**Frozen 운영 원칙 — Korean (pre-entwurf):**

> pi-shell-acp는 얇은 ACP 브리지다. delegate/resume/async 자체를 소유하지 않는다. 그 위의 MCP 표면과 orchestration은 소비 하네스(agent-config)의 책임이다.

Why the boundary moved: experience showed the delegate surface, target registry, identity preservation, and the MCP adapters that promote pi-side tools to ACP hosts all cluster around the ACP session lifecycle this repo already owned. Splitting them across two repos produced seam churn without a real boundary gain. See `## Entwurf Orchestration § Migration Plan` for the step-by-step transition.

Legacy env var note — `PI_DELEGATE_ACP_FOR_CODEX=1` was a pre-registry heuristic for Codex-via-ACP routing. It is superseded by the delegate target registry (`pi/delegate-targets.json`). If you see it in older notes, treat it as legacy.

---

## Scope

This repo owns two cooperating layers:

**Layer A — ACP bridge (original product surface):**
- provider registration in pi
- ACP subprocess lifecycle
- ACP initialize / resume / load / new session bootstrap
- prompt forwarding
- ACP event -> pi event mapping
- explicit pi-facing MCP injection (from `piShellAcpProvider.mcpServers` settings only) into every `newSession` / `resumeSession` / `loadSession` request
- minimal backend adapter selection for ACP launch + backend-specific session metadata
- bridge-local cleanup, invalidation, diagnostics

**Layer B — Entwurf orchestration (migrated in from agent-config):**
- delegate spawn (sync + async, Phase 0.5 mode contract) — `pi-extensions/delegate.ts`
- delegate core — registry resolution + Identity Preservation Rule — `pi-extensions/lib/delegate-core.ts`
- delegate target registry (SSOT) — `pi/delegate-targets.json`
- pi-tools-bridge — MCP adapter promoting pi-side tools to ACP hosts — `mcp/pi-tools-bridge/`
- session-bridge — cross-session Unix-socket MCP — `mcp/session-bridge/`
- 4-case session-messaging smoke — `scripts/session-messaging-smoke.sh`

This repo does **not** own:
- pi session UX conventions
- prompt reconstruction from full pi history
- hydration of backend transcript stores back into pi-local history
- tool ledgers / recovery ledgers
- Claude Code / Codex emulation
- generic MCP discovery / ambient MCP manager behavior (no `~/.mcp.json` scanning, no merging of arbitrary backend-side configs)

If a change expands Layer A or Layer B beyond the surfaces listed above — especially if it starts to look like "a general-purpose agent harness" — it is probably wrong. The "not a second harness" rule still applies: Layer B is a consolidated orchestration surface, not an expanding one.

---

## Hard Rules

1. **Surface name is singular**
   - provider id: `pi-shell-acp`
   - model prefix: `pi-shell-acp/...`
   - settings key: `piShellAcpProvider`
   - do not reintroduce legacy aliases
   - **docs/examples use the qualified form** `--model pi-shell-acp/claude-sonnet-4-6` (prefix routes to this provider — `--provider` becomes redundant and is dropped in examples). Internal smoke helpers that feed `ensureBridgeSession({modelId})` keep bare backend ids (`claude-sonnet-4-6`, `gpt-5.2`) because the bridge library contract is bare.

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

---

## Verification

### Two axes — both required

pi-shell-acp's verification has two distinct axes and **neither subsumes the other**.

| Axis | Shape | What it catches | Where |
|------|-------|-----------------|-------|
| **Protocol / command-line smoke** | `pi … -p '…'` invocations, `run.sh smoke*`, `test.sh` for MCP, tsc / check-* gates | wire-level regressions: ACP bootstrap order, backend selection, MCP validation, session continuity at the persistence layer, tool registration | inline here, `run.sh`, `mcp/pi-tools-bridge/test.sh` |
| **Agent interview** | a real Claude/Codex session inside `pi-shell-acp/...` answers [VERIFY.md](./VERIFY.md) Layer 0–4 questions | semantic-level regressions: does the agent *see* its tools, does it *read* the engraving, does pi-facing MCP surface actually reach the turn, does identity hold across turns | [VERIFY.md](./VERIFY.md) §1A |

**Why both.** A protocol smoke proves the pipes are connected. An agent interview proves the water arrives tasting like water. Each misses what the other catches:

- Protocol smoke can pass while the agent inside the session sees no MCP tools, no skills, and no engraving — because MCP injection fired at the bridge layer but the backend turn never surfaced them. An interview catches this immediately; a smoke never does.
- An interview can pass on one run and fail on another for reasons a smoke would have caught deterministically (version skew, `bootstrap path=new` when it should have been `resume`, MCP signature invalidation). An interview alone doesn't close the regression window.

**This is the lesson from the pre-Phase-0.5 VERIFY attempt.** A command-line smoke path was invoked with the correct token and the right flags, and everything looked green at the wire level — but the agent session inside had no working pi MCP surface and nothing caught it until we ran the interview. The fix (Phase 0.5) was a real one, not a test artifact. Do not regress this lesson by dropping the interview axis once protocol smokes become easy again.

### Axis 1 — protocol / command-line smoke

Run these after meaningful changes:

```bash
npm run typecheck
npm run check-registration
npm run check-mcp     # pure logic gate, no Claude/ACP subprocess
npm run check-backends
npm run check-claude-sessions -- /path/to/consumer-project
./run.sh smoke /path/to/consumer-project
```

This axis is cheap, fast, deterministic. Run on every meaningful change.

### Axis 2 — agent interview (VERIFY.md)

[VERIFY.md](./VERIFY.md) carries the interview script. Its §1A Layer 0–4 is the canonical interview: a real `pi-shell-acp/<model>` session answers about its environment, tools, pi-facing MCP boundary, multi-turn focus, and comparison to direct Claude Code. Pass criteria are in §1A.6.

- Run this axis at minimum: before cutting a release, after any change to bridge bootstrap / MCP injection / session continuity / engraving surface, after any ingestion from agent-config (see `## Entwurf Orchestration § Ingestion Gates`).
- Do **not** substitute a command-line smoke for the interview. The interview is the only path that proves what the agent *sees* once it is inside the session.
- Follow VERIFY §0A operating discipline: one command at a time, short sync turns via `delegate` / `delegate_resume`, never splice a manual `pi --session` uncovered boundary-check into the interview path.

A protocol smoke passing without the interview = "pipes connected." A full pass = both axes green.

### Exit Criteria — backend-related changes

For any change that touches backend selection, launch resolution, session bootstrap, smoke/setup scripts, or public dual-backend claims, the work is **not done** until all of the following are satisfied:

1. deterministic checks pass
   - `npm run typecheck`
   - `npm run check-registration`
   - `npm run check-mcp`
   - `npm run check-backends`
2. operator-facing runtime smoke passes for **Claude**
   - `./run.sh smoke /path/to/consumer-project`
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
cd /path/to/consumer-project
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
