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

Five surfaces move into this repo. Landing positions are provisional and will be finalized at ingestion time.

| Source (agent-config)                  | Destination (pi-shell-acp, planned)           | Purpose                                                          |
|----------------------------------------|-----------------------------------------------|------------------------------------------------------------------|
| `pi-extensions/delegate.ts`            | `entwurf/spawn.ts` (or similar)               | pi-native spawn entry                                            |
| `pi-extensions/lib/delegate-core.ts`   | `entwurf/core.ts`                             | shared core: registry resolution + identity lock                 |
| `pi/delegate-targets.json`             | `entwurf/targets.json`                        | SSOT allowlist of `(provider, model)` pairs                      |
| `mcp/pi-tools-bridge/`                 | `mcp/pi-tools-bridge/`                        | MCP adapter exposing entwurf + session_search/knowledge_search to ACP hosts |
| `mcp/session-bridge/`                  | `mcp/session-bridge/`                         | Claude Code ↔ pi Unix-socket session bridge                      |

**"One project" principle — preserved, not split.** agent-config's AGENTS.md Entwurf Orchestration section states: *"After migration both live together inside pi-shell-acp; the 'one project' principle is preserved, just with a new home."* This repo honors that contract. `pi-extensions`-equivalent surface and `mcp/*` adapters live side-by-side here; they are not to be split into sibling repos later.

### Phase 0.5 — sync/async mode contract (upstream, pending)

Phase 0.5 is implemented in agent-config (step 3 above), not here. Its outcome is what we ingest.

**Summary of the upstream work.** `delegate_resume` already operates asynchronously via native pi's `followUp` delivery path. Phase 0.5 names that reality: exposes an explicit `mode` parameter, defaults to `"sync"`, makes the existing async behavior opt-in. No new readiness/blocked state vocabulary, no durability layer, no full-async relay redesign — intentionally.

**What this repo accepts at ingestion.** The `mode: "sync" | "async"` contract on `delegate_resume` (to become `entwurf_resume`). Default `sync`. Async preserves current followUp semantics.

### Send-is-throw Principle (cross-session messaging)

Incoming with the artifacts above, already established upstream:

> Send is throw, not wait. An agent sends and moves on. If a reply is needed, the message itself asks the recipient to send back. If the work is truly important, use `entwurf` (own the outcome) instead of a message (notify and move on).

Practical consequence at ingestion: `send_to_session` and `list_sessions` move here; `wait_until` is intentionally not bridged to MCP. Blocking is a design smell in this model.

### Ingestion Gates

"Migration complete" is not a file-move event. Content moving into this repo must pass **both verification axes** (see `## Verification § Two axes`) at the new home before the migration markers are removed.

**Axis 1 — Protocol smoke (inherited from agent-config).** The smoke paths that validated entwurf in agent-config must pass against the same surfaces hosted here.

- `mcp/pi-tools-bridge/test.sh` — full protocol tests (15/15 baseline at `e5aa5a1`)
- entwurf spawn sentinel cell (sync + async variants) — the same sentinel artifact shape agent-config used at `e5aa5a1` (`/tmp/sentinel-phase05-cell1.json`)
- `send_to_session` 3-way matrix once step 4 of the ordering completes

These are deterministic gates. They fail fast and are cheap to re-run.

**Axis 2 — Agent interview (local to this repo's VERIFY.md).** A real `pi-shell-acp/<model>` session must answer VERIFY.md §1A Layer 0–4 with the new in-repo entwurf surface, not the agent-config one.

- Layer 0 — does the session read the engraving (`## Engraving`) and recognize entwurf as a first-class tool in this repo, not a referenced one?
- Layer 2 — does pi-facing MCP (now including `pi-tools-bridge` hosted here) actually reach the turn? Can the agent see and call entwurf/session_search/knowledge_search?
- Layer 3 — does identity preservation (the Resume Lock) hold when the entwurf resume is invoked from an in-session agent, not from a command-line `pi -p`?

Passing Axis 1 alone is not enough. Pre-Phase-0.5 we saw a green protocol smoke next to a broken interview; that failure mode is specifically what the two-axis rule exists to catch.

**Evidence requirement.** Each ingestion commit records Axis 1 sentinel artifacts + Axis 2 interview transcript summary in the commit body, the same way agent-config `e5aa5a1` recorded its smoke evidence. "It worked on my machine" is not evidence; artifact paths and token echoes are.

### Superseded Boundary

The previous `## Boundary — Bridge vs Consuming Harness` section (below, marked `[SUPERSEDED]`) is the pre-entwurf thesis. It is kept in place during the transition window as historical reference — do not delete it until migration step 7 completes.

---

## Boundary — Bridge vs Consuming Harness [SUPERSEDED: see Entwurf Orchestration]

> **Historical.** This boundary was the pre-entwurf thesis: "thin bridge, orchestration elsewhere." It is superseded by the `## Entwurf Orchestration` migration above, which consolidates delegate/registry/identity-lock/session-bridge surfaces into this repo. The body below remains as reference during the transition window and will be removed after ingestion completes.

**Public thesis (English, pre-entwurf):**

> pi-shell-acp is the thin ACP bridge product. It guarantees backend continuity and explicit MCP injection. Delegate/resume/async orchestration belongs to the consuming harness (currently agent-config), not to this bridge repo.

**운영 원칙 (Korean, pre-entwurf):**

> pi-shell-acp는 얇은 ACP 브리지다. delegate/resume/async 자체를 소유하지 않는다. 그 위의 MCP 표면과 orchestration은 소비 하네스(agent-config)의 책임이다.

### What this repo is NOT

- ❌ a delegate orchestration layer — `agent-config/pi-extensions/delegate.ts` is the source of truth for delegate / delegate_status / delegate_resume and async task lifecycle.
- ❌ the owner of MCP Phase-2 tools (`delegate_status`, `delegate_resume`, `list_sessions`) — those belong to `agent-config/mcp/pi-tools-bridge`.
- ❌ an async task registry or completion-notification system.
- ❌ a pi extension semantic emulation layer.
- ❌ a second harness. If a change makes this repo feel like a harness, it is probably wrong.

### Spawn authority lives in the consuming harness

Which (provider, model) a delegate call is allowed to spawn to — and which combinations auto-resolve from a bare model name — is owned by the **delegate target registry** in agent-config:

- File: `agent-config/pi/delegate-targets.json`
- Consumers: `agent-config/pi-extensions/lib/delegate-core.ts` (spawn path) and `agent-config/mcp/pi-tools-bridge/src/index.ts` (MCP surface).

This bridge deliberately does **not** read that registry. Once pi hands us a `(provider=pi-shell-acp, model, session)` triple we carry it; the decision of whether that triple was allowed lives upstream.

Historical note: there used to be a `PI_DELEGATE_ACP_FOR_CODEX=1` environment switch that controlled whether Codex delegates were routed through this bridge. That was a pre-registry heuristic. The registry is now the spawn authority; the env var is being retired in agent-config. If you see it referenced in older notes, treat it as legacy.

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
- broad multi-agent orchestration *(under revision — see `## Entwurf Orchestration`)*
- generic MCP discovery / ambient MCP manager behavior (no `~/.mcp.json` scanning, no merging of arbitrary backend-side configs)
- promotion of pi extension tools to Claude/Codex — build a separate MCP adapter for that and register it via `piShellAcpProvider.mcpServers` *(under revision — `pi-tools-bridge` is incoming; see `## Entwurf Orchestration`)*

If a change makes this repo feel like a second harness, it is probably wrong. *(This guard predates the entwurf migration. The entwurf surface landing here is intentional consolidation, not harness drift; the "not a second harness" rule still applies to everything outside that carved section.)*

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
npm run check-claude-sessions -- /home/junghan/repos/gh/agent-config
./run.sh smoke /home/junghan/repos/gh/agent-config
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
