# ACP backend adapter rail

The ACP plugin is one provider with backend adapters behind a common turn loop.
It is not a second harness and does not create another citizen or socket layer. The
host pi session already owns the record-backed citizen identity; each backend owns
its own process, auth, transcript, and native tool surface.

Claude is the reference adapter. Snowflake Cortex Code is the second shipped adapter.
Implementation history and audit chronology live in CHANGELOG, issues, and git; this
document keeps the current contract and its open evidence boundary.

## Boundary

| Layer | Owns |
|---|---|
| entwurf core | identity, facts, dispatch, rail choice, delivery evidence |
| ACP common loop | spawn, initialize, new session, model enforcement, prompt, event mapping, teardown |
| backend adapter | model routing, launch, overlay, carrier, backend settings, model enforcement details |
| backend runtime | credentials, subscription, transcript, native tools, native configuration semantics |

The common sequence is invariant:

```text
resolve adapter once
→ load backend settings and carrier
→ materialize backend overlay
→ spawn → initialize → newSession → enforceModel
→ prompt → event map → retain-or-teardown
```

No layer reconstructs a backend transcript, proxies credentials, scans ambient MCP
configuration, or grants tools through prose. Explicit `entwurfProvider.mcpServers`
and the callable schema are the tool truth.

## Adapter contract

Source of truth: `pi-extensions/lib/acp/backend-adapter.ts`.

| Method | Responsibility |
|---|---|
| `routeModel` | Claim a curated id and return the backend-native id. Zero or multiple owners fail loud. |
| `curatedModels` | Contribute rows to the single `entwurf` provider. Non-Claude backends use a reserved prefix. |
| `resolveAdapterSettings` | Parse only this backend's settings into an opaque value. |
| `resolveLaunch` | Return command/argv; honor only the backend's explicit override. |
| `launchEnvDefaults` | Supply static launch environment defaults. |
| `ensureOverlay` | Materialize session isolation and return spawn environment overrides. |
| `loadCarrier` | Return a short operator carrier or `null` when the backend has no carrier. |
| `buildSessionMeta` | Build optional `newSession._meta` from the already-loaded carrier. |
| `enforceModel` | Make the requested native model authoritative before the prompt. |
| `configSignatureFields` | Return a stable primitive map whose changes invalidate reuse. |

`backend.ts` resolves the adapter once at turn entry. Common config never branches on
backend-specific keys; `adapterSettings` remains opaque until handed back to its owner.
A connection, model, carrier, MCP declaration, or overlay-relevant setting change must
change the reuse signature rather than mutate a live incompatible session.

A streaming message begins with `stopReason: "pending"`. ACP's terminal set is mapped
explicitly: `end_turn → stop`, `max_tokens → length`, `cancelled → aborted`; refusal,
exhausted turn budget, unknown, and absent reasons end as errors. The original ACP
reason is preserved in `rawStopReason`. Returning to a default-success branch is a
contract violation.

### Prompt lifecycle — who may end a turn

Bootstrap (`initialize`, `newSession`, set-model) carries 30s wall-clock bounds: those
steps make no model progress, so a stuck one is a dead session. **The prompt carries
none.** A turn ends only on a lifecycle event:

| Ending | Behavior |
|---|---|
| the agent answers | mapped through the terminal set above |
| the operator aborts | ACP `session/cancel` first — the agent closes its own turn (`cancelled → aborted`); process-group teardown only after a bounded grace, so an abort always returns |
| the child dies / stdio ends | the turn fails naming the exit status and the session-scoped stderr tail — or an honest bounded absence when transport EOF wins the race — on both the new and the reuse path |

Elapsed time is not evidence of failure, and a silent turn is not a failed turn: tool
use, reasoning, and provider queueing all legitimately outrun any number we could pick.
Suspected stalls are handled by exposing progress, never by a killing timer.

A prompt-phase failure message is also part of the contract. pi classifies a failed
assistant message by matching its text against `RETRYABLE_PROVIDER_ERROR_PATTERN`
(`@earendil-works/pi-ai` `utils/retry`), and a "transient" verdict makes it replay the
WHOLE prompt from a cold session up to `retry.maxRetries` times. Our own prompt-phase
text must never read as transient — that pairing (absolute cutoff × blind retry) is what
turned one long turn into four in 0.13.0. Gates: `check-acp-prompt-lifecycle` (behavior,
with pi's own classifier as the oracle), `check-probe-ordering` (no production prompt
cutoff in source).

## Support contract (#81)

What "supported" means here, per declaration class. The classes are kept apart on purpose: one
undifferentiated "supported" column is what let a Claude PASS read as if it also certified Cortex.

| Surface | Declaration | Class | What a green actually says |
|---|---|---|---|
| Entwurf package | `0.17.0` | shipped baseline | the package contract these rows belong to |
| pi runtime | devDep exact `0.85.1`, peer `>=0.85.1 <0.86` | **exact** oracle + **closed range** | built and certified against 0.85.1; hosts inside the range are accepted, and the ceiling moves only on measurement |
| ACP wire SDK | `@agentclientprotocol/sdk 1.4.0` | **exact** | the shared wire oracle both adapters speak |
| Claude ACP adapter | `@agentclientprotocol/claude-agent-acp 0.75.1` | **exact**, bundled | the adapter we ship and certify; resolved before any PATH fallback |
| Claude Agent SDK | `0.3.257` (transitive) | **exact** oracle | the runtime risk surface behind the adapter |
| Anthropic SDK | `0.100.1` | **exact**, peer-resolution only | satisfies the Agent SDK peer floor (0.93.0+); never an API client here (gate L4) |
| Claude Code runtime | `>=2.1.217` (`entwurf.claudeCodeFloor`) | **floor** | below it, hook args are silently dropped; entwurf enforces this itself |
| Node | `>=24` (`engines.node`) | **floor** | single axis, derived everywhere else |
| Cortex Code | operator-installed CLI | **on-demand**, external | NOT a pinned dependency. Each LIVE record must name the exact CLI version it measured |

Current Cortex host reading: **`Cortex Code v1.1.52`, observed on the reference host `oracle`
(2026-08-19)**. This is an OBSERVATION of what happens to be installed, not a pin, not a range, and
not a direct LIVE certification — no Cortex evidence record is created by writing it down. It is
recorded here only so the on-demand row names a concrete number instead of an abstraction.

Reading rules that do not bend:

- **Claude PASS never certifies Cortex, and a Cortex SKIP never becomes a PASS.** They are separate
  evidence axes with separate records; Cortex stays outside the Claude release floor.
- **Exact** means one measured build. **Range** means a closed accepted interval. **Floor** means a
  minimum entwurf enforces itself. **On-demand** means the operator supplies the runtime and the
  evidence names its version — presence of an adapter certifies no external release.
- A declared pin is not evidence. Package/deterministic gates bind the declarations
  (`check-dep-versions`, `check-acp-sdk-surface`, the pack/install consumer gates); LIVE gates carry
  the runtime claim.

### Minimum core value

One provider identity, `entwurf`, with model-id routing to backend adapters. The host pi session is
already the record-backed socket citizen; the ACP plugin mints no second citizen, socket, or peer
layer. Backend differences stay behind `adapterSettings` and adapter methods, and the turn sequence
stays backend-invariant.

Supported: one real model turn; curated routing with authoritative model enforcement; a narrow
callable tool surface; explicit MCP wiring including the entwurf bridge; session reuse with
delta-only user history; operator cancellation with bounded cleanup; honest terminal/error mapping.

Not supported, by design: workflow ownership, planner state, a memory DB, transcript hydration,
credential proxying, or a second harness inside pi.

### Capability posture

`clientCapabilities: {}` is the support posture, not an oversight. Optional upstream features do not
become reachable merely because an adapter ships them — but they stay out of reach for **two
different reasons, and collapsing them would hide a real risk**:

- **Capability-gated.** AIR typed session failures, the 0.69.0 AIR file-change report, terminal
  output widgets and nested subagent transcripts each test a client capability entwurf does not
  send, so the adapter itself keeps the legacy path.
- **Advertised but never called.** Some surfaces carry no capability prerequisite at all — the
  `providers/list` / `providers/set` / `providers/disable` trio added in 0.70.0 is advertised
  unconditionally, and 0.71.0–0.73.0 add native subagents, async tasks, message-specific session
  forks, AI-generated session titles and permission-mode kinds on the same footing. 0.74.0–0.75.1
  extend the same list: the `authStatus` extension (0.75.0, #1080), Markdown-rendered usage
  statistics (0.75.0, #1085) and restored session forks (0.75.1, #1089). The `--hide-claude-auth`
  subscription refusal (0.74.0, #1079) is unreachable for a second reason — `[측정 2026-09-06]`
  entwurf passes that flag nowhere (repo grep, 0 hits). They are
  unreachable only because the common loop never invokes them (nor `logout`). Nothing upstream
  enforces that; it is our own call-site discipline, and it stops holding the moment we use one.
- **The one 0.73.0 → 0.75.1 change that DOES reach us:** context compaction is now surfaced as a
  synthetic ACP tool lifecycle (0.75.0, #991) — a `tool_call` with `kind: "think"`, title
  `Compact conversation`, and `_meta.contextCompaction` schema v1 — where it used to arrive as
  assistant text. Our mapper routes every `tool_call`/`tool_call_update` through
  `renderToolUpdate` (`event-mapper.ts`), so this is not a type break; what changes is what an
  operator SEES in a compacting turn. See §11-8 for the measurement.

Adopting either class requires a separate observed need plus a complete rendering/lifecycle/evidence
contract. An optional upstream feature is not a core-value gap.

### Bump / defer rubric

`claude-agent-acp latest` is not a work queue. Certify when at least one holds:

- a turn/session/error path reachable under the default capability posture changes;
- the Claude Agent SDK, ACP SDK, peer resolution, pi floor, or backend process contract moves;
- a security, compatibility, or observed runtime defect requires the release;
- accumulated inactive minors are best folded into the next meaningful certification.

Otherwise record and defer. Every certification separates declared pins, deterministic/package
evidence, Claude LIVE aggregate evidence, and Cortex direct on-demand evidence (with its CLI
version). Per-bump measurements live in the ROADMAP **Dep bump(별도 트랙)** ledger.

### Bridge reachability is part of the contract

Explicit entwurf-bridge connectivity inside an ACP turn is core value, so it is measured rather than
assumed. `command -v` succeeding is not evidence: a launcher can resolve and still fail to exec (a
relocated package-manager shim deriving its target from `$0` exits 127), which leaves a turn with no
`mcp__entwurf-bridge__*` tool at all while every ownership check reads green. Both doctors therefore boot the exact configured stdio invocation — `command`, `args`, and
`env` — and require the full bridge verb set back over one shared leaf
(`./run.sh probe-bridge-command <cmd>` runs a simple command standalone; the agy doctor passes
its JSON invocation). The probe waits for a valid MCP `initialize` response before it sends
`notifications/initialized` and `tools/list`; a tools response alone is not boot evidence.

- **agy** probes every configured candidate invocation.
- **pi** probes every effective stdio invocation, including a legacy managed path or unowned
  override. Runtime truth says whether the command pi will launch works; ownership separately says
  whether entwurf may repair or normalize it.

entwurf never repairs a launcher it does not own — a foreign one is reported fail-loud with the
operator's repair named.

## Shipped adapters

| Seam | Claude | Cortex Code |
|---|---|---|
| Model ids | unprefixed `claude-sonnet-5`, `claude-opus-5` | `cortex-auto`, `cortex-claude-opus-5`, `cortex-claude-sonnet-5`, `cortex-openai-gpt-5.4`; prefix stripped before set-model |
| Launch | bundled `claude-agent-acp`; `CLAUDE_AGENT_ACP_COMMAND` override | `cortex acp serve`; optional connection; `CORTEX_ACP_COMMAND` override; never a launch-time `-m` |
| Model authority | per-turn ACP set-model | per-turn ACP set-model; an unavailable curated id fails before prompt |
| Carrier | engraving in `_meta.systemPrompt` | no system-prompt carrier; engraving rides the first-user augment |
| Overlay | `CLAUDE_CONFIG_DIR` whitelist, configured-empty hooks, native memory hidden | session-scoped isolated HOME + `SNOWFLAKE_HOME`, private `cortex/mcp.json`, measured-minimum auth passthrough |
| MCP | explicit wire `mcpServers` | explicit declarations projected to private `mcp.json` because Cortex ignores the wire field |
| Backend setting | none | `cortexConnection`; env override wins and participates in the signature |

### Claude

The bundled adapter resolves before any PATH fallback. Its overlay retains only the
auth/runtime state required by the Claude Agent SDK and hides operator memory, hooks,
agents, history, and local settings. Rich project/operator context rides the first-user
augment; the system carrier stays short to avoid changing billing semantics.

The carrier owns its own leading boundary. A string `_meta.systemPrompt` replaces the
`claude_code` preset, but the SDK still prefixes a fixed identity sentence and joins the
two with nothing, so the loader opens every rendered carrier with one blank line. The
template cannot supply it — the render is trimmed so operator whitespace never drifts the
reuse signature. That same rendered string is what `bridgeConfigSignature` folds and what
`buildSessionMeta` sends; normalizing it at either hop desynchronizes the wire from the
signature.

`clientCapabilities` intentionally remains empty. Terminal-output widgets and nested
subagent transcripts are therefore not requested. Enabling either is a separate
rendering contract, not a capability bit flip.

### Cortex Code audit (D1–D10)

The original audit labels remain useful coordinates for source comments and gates:

| Audit | Landed contract |
|---|---|
| D1–D2 | Isolated HOME hides operator-global Claude/Cortex skills and settings; install-directory plugins remain a host fact. |
| D3 | Refuse `CORTEX_HOME` whenever present, including empty. |
| D4 | Author `autoUpdate: false`; launch only `cortex acp serve`. |
| D5–D6 | Pass through measured-minimum local auth; entwurf never runs or supplies authentication. |
| D7 | Four curated rows; enforce the stripped native id before prompt. |
| D8 | Credential boundary is AGENTS Hard Rule 9 and the ACP Plugin Boundary. |
| D9 | Project explicit MCP declarations into private `cortex/mcp.json`; wire `mcpServers` is ignored upstream. |
| D10 | Restore real operator HOME only for `entwurf-bridge`, so the isolated child still sees the garden store. |

Cortex containment was measured against the live CLI rather than copied from Claude:

- **Dual HOME:** the child receives an isolated `HOME` and `SNOWFLAKE_HOME`. Global
  `~/.claude`/`~/.cortex` skills, hooks, settings, and operator `cortex/mcp.json` are
  outside the session; explicit cwd project scope remains visible.
- **`CORTEX_HOME` presence refusal:** Cortex gives it precedence over
  `SNOWFLAKE_HOME`; even an empty ambient value can make ownership ambiguous.
- **Auth passthrough:** only `connections.toml`, optional `config.toml`, and
  `cortex/cache/credential_cache` are symlinked through. This narrows reachable paths;
  it is not a read-only mount and entwurf never supplies the credential.
- **Launch integrity:** the overlay authors `autoUpdate: false`, preventing a CLI
  replacement in the middle of a turn. The launch is exactly `cortex acp serve` plus
  an optional connection; protocol initialization fails loud if a TUI was started.
- **MCP projection:** Cortex's ACP server ignores wire `mcpServers`, so the adapter
  exact-writes an overlay-private `cortex/mcp.json`. Non-stdio declarations fail before
  spawn. Only the `entwurf-bridge` entry receives the real operator HOME required to
  see the garden store.
- **Carrier:** Cortex has no `_meta.systemPrompt` contract. The engraving is placed at
  the head of the first-user augment; claiming a system-prompt engraving is false.

Cortex's bundled install-directory plugins are outside any HOME overlay and remain a
host fact. Also unclaimed: project-hook behavior on every host, the semantics of its
caller-session `_meta`, and cross-machine certification.

## 11-7. Readiness boundary

A backend can return `newSession` before its declared MCP server is callable. This was
observed intermittently on the Claude rail and directly on Cortex's private `mcp.json`
path. Neither `claude-agent-acp` 0.75.1 nor the Cortex landing adds a client-side
readiness fence over a session's declared MCP servers, and entwurf's common loop
calls `mcpServerStatus()` nowhere.
(Re-measured at the 0.73.0 → 0.75.1 bump, not inherited from the previous one — and the
0.70.0 → 0.73.0 argument is not reused either. `mcpServerStatus` call sites in
`src/acp-agent.ts` are **2 at both v0.73.0 and v0.75.1** `[측정 2026-09-06, git grep -c]`;
they first appeared in 0.71.0 via `0cbbaf3` (MCP OAuth, LLM-25012), so the ADAPTER calls it
where it once did not. Both were re-read at `v0.75.1 src/acp-agent.ts:1736` and `:1829`
(the 0.73.0 coordinates were `:1618` and `:1711`): the first sits inside
`authenticateMcpServers` behind `supportsMcpOAuth(query)` and skips every status that is not
`needs-auth`; the second polls a SINGLE named server to `connected` under an OAuth deadline.
Neither waits on every declared server before `newSession` returns. That is an auth
handshake, not a readiness fence, so the boundary below is unchanged. The other reachable-surface findings also re-measured:
AIR typed failures and the AIR file-change report stay capability-gated and
unadvertised by entwurf; `providers/set` / `providers/disable` stay advertised
unconditionally and uncalled; native subagents, async tasks, session forks, session
titles, permission-mode kinds and clear-context planning are all new-but-uncalled.
This bump changes no readiness behavior and closes no part of #72.)

### 11-7-a/b. Instrument and first measurement

The ordering probe is an **instrument**, not a fix. It separates:

1. client request/response ordering;
2. backend MCP receive/reply markers;
3. the first prompt/tool decision;
4. probe admissibility (the test itself did not create the race).

Its first paired measurement was inconclusive. Do not convert that into “no race” or
“the adapter fixed it.” A green intermittent run measures one sample; a red run proves
the symptom remains.

### 11-7-c. CLI snapshot producer

The B-name-snapshot producer is admissible only when the run pins the real target
executable and digest, refuses ambient overrides, preserves argv/stdin/stdout/stderr and
exit/signal behavior, bounds NDJSON framing, scrubs only the exact probe env allowlist,
and timestamps snapshot/prompt hand-offs inside the downstream write callback. One
post-wire init snapshot may support the controlled-absence row; malformed, duplicate,
pre-wire, unarmed, or target-mismatched snapshots invalidate the run rather than proving
absence. `check-probe-cli-shim` is the detailed producer oracle: its 20 direct
`[CHECK:*]` assertions remain, while their verification-infra replants were deliberately
removed by #70. `probe-ordering.json` retains only the product-subject no-production-prompt-cutoff
replant consumed by `check-probe-ordering`.

Current probe contract and gates:

- `check-probe-ordering` — interval/envelope and marker ordering;
- `check-probe-cli-shim` — CLI shim admissibility and environment boundary;
- `smoke-acp-ordering-probe-live` — opt-in paired observation.

Until a causal fix lands, release gates continue to exercise real MCP availability and
fail when the callable surface is absent. Do not add sleeps or infer readiness from
`newSession` latency.

## Verification

Deterministic floor:

```bash
pnpm run check:full
./run.sh check-acp-provider-surface
./run.sh check-acp-sdk-surface
./run.sh check-acp-session-reuse
./run.sh check-acp-stop-reason
./run.sh check-acp-cortex
./run.sh check-gate-qualification
```

Live axes:

```bash
LIVE=1 ./run.sh release-gate /path/to/scratch --cut
LIVE=1 ENTWURF_ACP_CORTEX_CONNECTION=<conn> \
  ./run.sh smoke-acp-cortex-live
```

The aggregate release gate is Claude-backed so a host without Cortex/Snowflake auth
can run the package floor. That means Cortex is **on demand**, not optional evidence:
a cut that changes or ships the Cortex rail must run and read its dedicated smoke.
Per-cut counts, digests, versions, and host observations belong in BASELINE/CHANGELOG,
not this standing contract.

## 11-8. Compaction is a tool lifecycle (0.75.0 onward)

The one change in the `0.73.0 → 0.75.1` bump that REACHES the common loop. Upstream #991
(`f74a517`) replaced compaction's assistant text with a synthetic ACP tool call: `kind:
"think"`, title `Compact conversation`, `_meta.contextCompaction` schema v1.

`[측정 2026-09-06, oracle, adapter 0.75.1, claude-sonnet-5]` one live `/compact` turn emitted
exactly two notifications (`tool_call` in-progress → `tool_call_update`), and those verbatim
objects replayed through the production `applyAcpSessionUpdate` produced a
`[tool:start] Compact conversation` / `[tool:…] Compact conversation` notice pair. No new
mapper branch is needed — `renderToolUpdate` routes every tool call regardless of `kind` —
and `_meta.contextCompaction` is dropped by the mapper, so no accounting path sees it.

What changed is therefore what an OPERATOR sees in a compacting turn, not what entwurf
computes. The post-compaction occupancy refresh is NOT new: `v0.73.0 src/acp-agent.ts:3460`
already emitted a `usage_update` at `compact_boundary` and 0.75.1 still does
(`dist/acp-agent.js:2740-2752`, now reading `compact_metadata.post_tokens` instead of a
`getContextUsage` control request), so the shrinking-`used_end` case that
`backend.ts:1286-1288` names as #96's weak floor gains no new trigger here.

Receipt, limits and the `completed`-branch gap: `scripts/raw-acp-compaction-measure/README.md`.

## Open work

- causal MCP-readiness diagnosis and, only with proof, a backend-invariant fence;
- broader installed-host and cross-machine Cortex evidence;
- any future Codex managed native-citizen lane—separate from ACP; 0.14.0 does not ship one;
- persisted ACP resume/load, which is not implemented by today's in-memory reuse.
