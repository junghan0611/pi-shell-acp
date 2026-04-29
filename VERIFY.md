# VERIFY.md

Replicant-testing-replicant verification guide for `pi-shell-acp`.

This document is a **working document, not a metrics document**.
Even if scripts break, an agent that follows these steps and reads the results should be able to immediately determine:

- Whether ACP is broken in single-turn mode
- Whether multi-turn sessions are genuinely continuing
- Whether cross-process continuity is working
- Whether bridge invariants are not leaking
- Whether tool call / event mapping is visible
- Whether processes/cache are not left behind as garbage
- Whether pi session records are usable as a shared memory axis for andenken embedding

## Why this document exists — Replicant testing replicant

VERIFY.md is the **agent-driven** verification surface (BASELINE.md is the operator-driven one). One ACP-bridged model runs the script against another ACP-bridged model and writes down what it sees. Both pass through the same `pi-shell-acp` carrier; if the bridge is faithful, **two replicants looking at the same mirror produce the same description of the mirror**. Cross-validation between the two transcripts (verifier vs subject) becomes the strongest **in-bridge cross-validation** evidence so far that the bridge transmits environment truth without distortion. It is not external evidence — both verifier and subject share the same bridge, the same MCP servers, the same operator-config overlay, and any uniform corruption of those would not surface here. See "Evidence Levels" below for what each kind of test does and does not prove.

A run is meaningful when it satisfies three conditions at once:

1. **Same harness invariant**: the verifier and the subject agree on what they see — same MCP servers enumerated, same tool boundary, same operator-config isolation. Disagreement here means the bridge is leaking different views to different identities, which is a regression even when individual smoke gates pass.
2. **Cross-process session reuse**: a single `(sessionKey, backend, modelId, bridgeConfigSignature)` tuple maps to one ACP child for the whole verification run. `pgrep -af claude-agent-acp` delta should be 0 for a verifier already holding a bridge session — see §10.3 for the formula.
3. **Long-turn fact retention**: 8+ turns / 3+ early facts / verbatim recall, including a string injected before turn 5. This is `usage_update`-driven occupancy plus disabled compaction working as one — if either layer regresses, this gate breaks first.

Anything weaker than this — single-turn smoke, individual-turn tool calls, or self-recognition without a peer to compare against — confirms wiring but not bridge faithfulness. The replicant pair is the smallest unit that exercises the bridge invariant end-to-end.

## Strengthened verification rules (post-0.4.1)

These supersede the per-section rules they touch — the original sections are kept for context, but the rules below are what must hold:

- **§1A.4 Layer 3 pass criterion** is **8 turns / 3+ early facts / one verbatim string injected before turn 5**, not 5 turns. Real bridge runs at 9-turn / 4-fact / 100% recall with the current code; lowering the bar to 5 turns hides regressions.
- **§10.3 process-count formula** counts **distinct alive `(sessionKey, backend, modelId, bridgeConfigSignature)` tuples**, not entwurf taskIds. A single `entwurf` + N `entwurf_resume` calls on the same target reuse one child (see `acp-bridge.ts:2340` — `bridgeSessions.get(sessionKey)` + `isSessionCompatible`). Delta=0 against a verifier that was already holding the bridge session is the **expected** state, not an under-count.
- **§1A.5 Layer 4 prerequisite**: a verifier already running through `pi-shell-acp` cannot dispatch to direct Claude Code via standard MCP tools — it can only call its sibling via entwurf. Layer 4 requires either a human in the loop or a verifier that holds both transport handles. Attempting Layer 4 from inside a single bridged session produces meaningless symmetry, not comparison.
- **§12.1 `PI_ENTWURF_CHILD_STDERR_LOG` self-spawn limit**: `export` from a shell that is already bound to a running bridge process does **not** propagate into that bridge — the env must be present at bridge-process spawn time. Either restart the parent session with the env exported, or run VERIFY.md from a plain shell that has not yet bound the bridge.

## Evidence Levels

Every claim in this document — and every History entry — implicitly sits on one of these rungs. Make the rung explicit so neither narrative nor reader overreaches.

| Level | What it is | Closes | Does not close |
|---|---|---|---|
| **L0** | Narrative / self-report | Author/agent description of the system | Anything that depends on actual behaviour |
| **L1** | Transcript cross-check | Two or more bridged identities agree on what they see | Echo chamber risk (shared prompt, shared carrier) |
| **L2** | Objective MCP tool call | Real on-disk / on-socket payload returned through the bridge | Shared-implementation corruption (same buggy bridge for both sides) |
| **L3** | On-disk / process / socket corroboration outside the bridge | What the bridge says ↔ what `ls`, `pgrep`, `lsof`, raw socket connect, session JSONL on disk say | Time-extended drift (auth, version, cache, memory) |
| **L4** | Human or direct-native side-by-side comparison | A real person (or a non-bridged direct Claude/Codex) reaches the same answer the bridge does for matched prompts | Production-shape workload (long sessions, tool bursts, fault injection) |
| **L5** | Long-haul soak | The bridge stays correct under hours-to-days of real use, including partial failures and concurrent multi-session pressure | Nothing higher proposed yet — this is the operational ceiling for now |

The History rows so far reach **L1** (intra-Anthropic, 2026-04-27) and **L2** (cross-vendor + reverse-direction MCP calls, 2026-04-29). L3 is partially exercised by §10 process snapshots and §11 session-file checks but not as a coherent verifier loop. L4 needs the operator (BASELINE.md territory) or a separate non-bridged path. L5 has not been run.

When you write a new History entry or a new section, mark which rung it stands on. "L1 only" is fine — it is honest. "L2 reached" is stronger evidence than "L1 only" but does not silently imply L3 is also true.

---

## 0A. Execution Policy — Transparent Mode (Real-World Baseline)

The verification in this document is not a benchmark. In production, we continuously exchange **short sync turns** like `entwurf` / `entwurf_resume` to check state, and stop immediately to isolate the cause before resuming when something looks off.

This document records only **verification intent (what we're looking at) and pass criteria (how to judge)**. The execution shape is determined by the agent using the most reasonable tools in its environment. The same intent can be verified in different ways — as long as the pass criteria are met.

### Default Execution Shape — entwurf orchestration

- Single-turn verification: one `entwurf(provider="pi-shell-acp", model="<M>", mode="sync")` call
- Multi-turn verification: first turn via `entwurf`, subsequent turns via `entwurf_resume` with the same `taskId`
- Different backend verification: same pattern with only provider/model changed (e.g., `pi-shell-acp/codex-...`)

### What NOT to Do — Bypassing the Operational Path

The following patterns **bypass the delegation logic itself** that we're trying to verify. Even if continuity appears to hold on the surface, these are not the real operational path (entwurf → entwurf_resume), so passing does not mean production is healthy.

- ✗ Creating session files directly with `mktemp /tmp/pi-shell-acp-verify-XXXXXX.jsonl`
- ✗ Manual calls of the form `pi -e <REPO> --session <FILE> --model <M> -p '...'`
- ✗ Faking multi-turn by passing the same session file twice

In the past, having these commands written out directly caused agents to copy them verbatim and bypass the operational path. This document contains only intent and pass criteria. Shell commands are retained only where they are integral to the verification, such as boundary checks (§6).

The manual `pi --session` path is only used in two cases:
- When the entwurf path itself is broken and an isolated debug bypass is needed
- §6-style boundary verification that requires directly hitting the bridge's internal API

### Operational Principles

- **Execute one command at a time.** (Do not chain multiple steps with `;`)
- **Preserve full stdout/stderr** at each step.
- If something goes wrong, do not proceed to the next step — **stop and hold**. (Preserve session/cache/process state first if needed)

### Verification Prompt Wording — Avoid Safety Interpretation Contamination

When injecting a fact and retrieving it during continuity verification, use **plaintext facts that do not trigger model safety interpretation**. Avoid the following vocabulary:

- ✗ `secret token`, `test-token-123`, `password`, `API key`, `credential`
- ✗ Meta-directives like "secret", "sensitive", "do not leak"

Such wording causes Claude to interpret the prompt as a prompt injection / secret exfiltration / safety violation and respond with "I don't know" or "I won't share that." This makes **continuity look broken even when it is alive** — safety refusal masquerades as continuity failure. This actually happened once (`test-token-123` verification received a refusal and was misdiagnosed as a delegation logic failure).

Instead, use **non-sensitive plaintext**:

- ✓ `The password is owl → reply in one word → owl`
- ✓ Code names / colors / animal names / ordinary words / arbitrary alphanumeric tokens (no semantic signals)
- ✓ Force the first turn response to a short ack (`READY`, etc.)

Key point: do not mix continuity verification and safety behavior verification in a single prompt.

### bridge continuity vs semantic continuity — Do Not Treat as the Same Thing

These two layers are treated separately:

- **bridge continuity**: same `sessionKey` / persisted record hit / same `acpSessionId` / `bootstrap path=resume|load`
- **semantic continuity**: a fact given in a previous turn can be retrieved in a subsequent turn

Bridge continuity can be alive while semantic continuity is broken (the wording contamination case above). The reverse is also possible. Do not extrapolate a pass in one layer as a pass in the other. When observability of the bootstrap path (§12 item 1) is weak, it's easy to confuse the two layers and misdiagnose wording contamination as continuity failure. When in doubt, change the wording and try once more, and also check the `[pi-shell-acp:bootstrap]` lines in bridge stderr.

## 0. Quality Criteria

What we want is not simply "invoke Claude Code."

The goals are:

1. **Session continuity at the agent-shell level**
   - Continuity through ACP session resume/load/new, not re-throwing a blob of text
2. **Preservation of pi harness semantics**
   - pi session files, transcripts, and memory pipeline remain as a shared common axis
3. **restart-safe**
   - Even when the process changes, the same pi session should resume as the same ACP session as much as possible
4. **Thin bridge**
   - Do not build a second harness inside this repo
5. **Capability exposure boundary is explicit**
   - pi custom tool / user MCP visibility is determined solely by `piShellAcpProvider.mcpServers` configuration
   - No automatic `~/.mcp.json` loading
6. **Operational hygiene**
   - No orphan subprocesses, no excess persisted session garbage

---

## 1. Setup

pi-shell-acp supports two legitimate install paths. Pick the one that matches the machine you are on. Both paths end in the same runtime state (a valid `.pi/settings.json` with `piShellAcpProvider.mcpServers` wired) — they differ in who owns the checkout and whether you intend to edit it.

| Path | Who | Shape | Example target |
|------|-----|-------|----------------|
| **A — Consumer** | end-user of pi | `pi install git:…` + one `run.sh install .` | fresh pi machine (Oracle server, new laptop) |
| **B — Developer** | contributor / first user | `git clone …` + `pi install ./` + `run.sh install …` | primary dev machine (ThinkPad, NUC) |

### 1.1 Path A — consumer install

Use when you want to *use* pi-shell-acp but will not edit it.

```bash
# 1. register with pi (pi auto-clones + installs deps into its managed checkout)
pi install git:github.com/junghan0611/pi-shell-acp

# 2. wire the bundled mcpServers into a consumer project
cd /path/to/consumer-project
~/.pi/agent/git/github.com/junghan0611/pi-shell-acp/run.sh install .

# 3. verify model surface
pi --list-models pi-shell-acp

# 4. one-turn smoke
pi --model pi-shell-acp/claude-sonnet-4-6 -p 'ok만 답하세요'
```

Expected:
- step 1 — pi prints package install messages; `pi list` afterwards shows `git:github.com/junghan0611/pi-shell-acp` under `User packages` with a path under `~/.pi/agent/git/github.com/junghan0611/pi-shell-acp`.
- step 2 — `install: added piShellAcpProvider.mcpServers.pi-tools-bridge` + `install: added piShellAcpProvider.mcpServers.session-bridge` + `install: updated <project>/.pi/settings.json`.
- step 3 — curated model surface prints (claude-sonnet-4-6, claude-opus-4-7, gpt-5.2, gpt-5.4, gpt-5.4-mini, gpt-5.5).
- step 4 — bridge response of `ok`.

Notes:
- The checkout path `~/.pi/agent/git/github.com/junghan0611/pi-shell-acp` is pi-managed. Do not edit files there on a consumer machine — `pi update` would overwrite local edits.
- Step 2 is still required after `pi install git:…`. `pi install` only adds the package to `~/.pi/agent/settings.json#packages`; it does not pre-wire the per-project `piShellAcpProvider.mcpServers` entries. `./run.sh install .` is what produces a working ACP-visible MCP surface in the current project.

### 1.2 Path B — developer install

Use when you will edit this repo and want a fast inner loop (`npm run typecheck`, `./run.sh smoke-all`).

```bash
# 1. clone + deps
git clone https://github.com/junghan0611/pi-shell-acp /path/to/pi-shell-acp
cd /path/to/pi-shell-acp
npm install   # or: pnpm install

# 2. register the local checkout with pi (relative or absolute path both fine)
pi install ./

# 3. wire mcpServers into a consumer project
./run.sh install /path/to/consumer-project

# 4. deterministic gates
npm run typecheck
npm run check-mcp
npm run check-backends
npm run check-registration

# 5. dual-backend runtime smoke gate
./run.sh smoke-all /path/to/consumer-project
```

Expected:
- step 2 — the checkout path is added to `~/.pi/agent/settings.json#packages`; `pi list` shows it under `User packages`.
- step 3 — same log lines as Path A step 2.
- step 4 — each `check-*` gate prints `[check-*] N assertions ok` (typecheck emits nothing on success).
- step 5 — `[smoke-all] Claude + Codex runtime smokes: ok`.

Re-running step 3 is idempotent. User-authored `mcpServers.<name>` overrides with a different command survive the re-run and are annotated `preserved (user override: …)`. `./run.sh remove /path/to/consumer-project` deletes only entries whose command matches the repo-authored launcher path; user overrides stay.

### 1.3 Variables (referenced by the rest of this document)

```bash
# Path A
export REPO_DIR=$HOME/.pi/agent/git/github.com/junghan0611/pi-shell-acp
# Path B (pick one)
# export REPO_DIR=/path/to/pi-shell-acp

export PROJECT_DIR=/path/to/consumer-project
export CACHE_DIR=$HOME/.pi/agent/cache/pi-shell-acp/sessions
mkdir -p "$CACHE_DIR"
```

### 1.4 Setup shortcut (either path)

From the checkout:

```bash
cd "$REPO_DIR"
./run.sh setup "$PROJECT_DIR"
```

`setup` is a convenience that runs `install` + `smoke-all` in sequence, so a green `setup` implies both the settings.json wiring and the dual-backend runtime are healthy.

### 1.5 Pre-verification snapshot — capture once, before §3

Every verification run produces evidence by **comparing state before and after**. Capture these baselines **immediately before §3 begins** — once they're missed, §5/§10 lose their comparison axis for the rest of the run.

```bash
export BEFORE_CACHE=$(find "$CACHE_DIR" -maxdepth 1 -type f | wc -l)
export BEFORE_ACP=$(pgrep -af claude-agent-acp | wc -l)
export BEFORE_CODEX=$(pgrep -af codex-acp | wc -l)
echo "before: cache=$BEFORE_CACHE claude-agent-acp=$BEFORE_ACP codex-acp=$BEFORE_CODEX"
```

Preserve these three numbers in your verification log. §5.1 (cache delta), §10 (process delta) all reference them.

### 1.6 Turn map (sequential run)

When §3 → §4 → §8 → §1A.4 are run sequentially against a single target as one verifier session, the global turn index runs from 1 to 10. Each section's local index ("first turn") is relative to that section, not the global run.

| Global turn | Section | Intent |
|---|---|---|
| 1 | §3.1 | SessionStart hook ack |
| 2 | §3.2 | Basic tool call (date) |
| 3 | §4.1 (1) | Inject fact |
| 4 | §4.1 (2) | Retrieve fact |
| 5 | §4.1 (3) | Update fact |
| 6 | §4.1 (4) | Retrieve updated fact |
| 7 | §8.5 | List visible MCPs |
| 8 | §8.5 | List MCPs again — consistency check |
| 9 | §1A.1 | Self-awareness |
| 10 | §1A.4 | Multi-fact recall (uses turns 3–5 facts) |

If the verifier strictly needs a fresh ACP session inside this sequence, switch to a different target (e.g. `claude-opus-4-7` or `gpt-5.2`) at the section boundary — see §3 operational note on the per-`(provider, model)` uniqueness gate.

### 1.7 Cross-install / cross-backend parity (optional but high-value)

Three axes to compare a fresh self-awareness report against:

1. **Same backend, different install path.** Path A (`pi install git:…`) on one machine vs Path B (`git clone + pi install ./`) on another. Same answer expected — the install path must be invisible to the bridged model.
2. **Same backend, different machine.** Two `pi-shell-acp/claude-sonnet-4-6` instances (e.g. local + Oracle). Identical native tool list, identical MCP server list, identical 8 MCP tool functions.
3. **Different backend, same bridge.** `pi-shell-acp/claude-sonnet-4-6` vs `pi-shell-acp/gpt-5.4` (or any Codex target). Same harness identification (`pi-shell-acp`), same MCP servers (`pi-tools-bridge` + `session-bridge`), same 8 MCP tool functions — but **different** native tool surface (Claude: `Bash/Read/Edit/Write/Skill`; Codex: `exec_command/write_stdin/apply_patch/update_plan/request_user_input/list_mcp_resources/read_mcp_resource/...`) and **different** MCP namespace convention (`pi-tools-bridge` with hyphens vs `pi_tools_bridge` with underscores — see §8.4 verified property).

Pass:

- Axes 1 + 2: structurally identical reports.
- Axis 3: harness + MCP server names + MCP tool function count match; backend-native tool surfaces are **backend-specific**, not normalized. If a Claude session reports `apply_patch` as native (or a Codex session reports `Bash` as native), the bridge has accidentally normalized the tool surface — that is a fail, not a feature.
- Axis 3 reverse-direction evidence: a Codex verifier can call `entwurf` against a Claude target (or vice versa), the spawn succeeds, taskId is issued, and the verifier can parse the subject's self-report into a comparison table. Confirmed empirically 2026-04-29 — Codex on Oracle spawned Claude via entwurf, captured the self-report, and produced its own meta-analysis matching the §14 pass criterion 11 axis. This is bidirectional cross-vendor orchestration working through one bridge.

This is the matrix described under "Diversifying the verifier matrix" near the end of this document. Both axis-3 directions (Anthropic verifier × Codex subject and the reverse) are now closed; only intra-Codex remains, with marginal added value.

---

## 1A. Main Agent Evaluation — Is `pi-shell-acp` Claude Strong Enough?

This section moves the evaluation questionnaire from the llmlog into this repo's operational document.
The core question is one:

> **When Claude is connected through pi via ACP, is it strong enough as the main coding agent?**

This evaluation is separate from the continuity smoke. If smoke proves "sessions continue," this questionnaire examines **tool self-awareness / native tool usability / pi-facing MCP boundary awareness / long-turn focus / quality relative to direct Claude Code**.

The execution shape follows §0A — Layers 0–3 start with one `entwurf` for a single target (`pi-shell-acp/claude-sonnet-4-6`) and continue via `entwurf_resume` with the same taskId for multi-turn. Layer 4 is a comparison with direct Claude Code, so it uses a separate path.

### 1A.1 Layer 0 — Self-Awareness at Session Start

Intent:
- Can Claude explain which harness/tool environment it is currently in?
- Does it confuse Claude Code native tools with pi-facing MCP tools?
- Does it avoid assertively reproducing the system prompt / project context it cannot see?

Ask all three freely in a single session (environment self-awareness / MCP visibility / upstream instruction awareness). Explicitly prohibit guessing.

Pass:
- Mostly recognizes native tool family, says "I don't know" for things it doesn't know
- Answers MCP visibility only as the current configuration allows (says "not visible" if no config)
- Carefully describes the type of upstream instructions, does not assertively reproduce internal prompts

Fail:
- Claims a tool exists that does not
- Conflates pi custom tools and native tools in explanations
- Hallucinates MCP visibility

#### 1A.1.1 Codex objective wiring check (when backend = codex)

The interesting evidence layer for Codex is **direct MCP tool calls** — calling the bridged tools and confirming they return real data, not just that the model claims they exist. Self-report can echo-chamber across instances; an actual tool invocation cannot be dismissed as self-report alone. (A uniformly wrong shared bridge could still produce uniformly wrong tool-call payloads — see "Evidence Levels" L2 vs L3 — so this is one rung up the ladder, not the top.)

> **Calibration note (2026-04-29).** A previous version of this section suggested using `list_mcp_resources` as the objective channel. That tool reports MCP-server *resources* (data records), not the server / tool registry. `pi-tools-bridge` and `session-bridge` expose only tools, no resources, so `list_mcp_resources` returns `{"resources":[]}` — empty is the correct answer there, not an absence-of-bridge signal. Use the recipe below instead.

Codex objective wiring recipe (verified 2026-04-29):

1. Call `mcp__pi_tools_bridge__entwurf_peers` with no args.
   - Pass: response includes `controlDir`, integer `count`, and a `sessions` array with real `sessionId` UUIDs and absolute `socketPath` values.
2. Call `mcp__session_bridge__session_info` with no args.
   - Pass: response includes `Session ID` (UUID), `Session Name` (`pi-shell-acp` for a bridged session), and an absolute socket path under `~/.claude/session-bridge/`.

Both calls succeeding with real payloads is stronger evidence than any number of self-reports — the bridge is not just visible-in-prompt, it is wired and operational, and the data flowing back is consistent with on-disk state.

Asymmetry note: Claude Code does not expose an equivalent native introspection tool through the same path. Claude verification stays on self-report + indirect evidence (`entwurf_peers` / `session_info` are still callable on the Claude side, but the agent must initiate the call rather than the verifier — pass criteria identical). The asymmetry is itself an operational fact: Codex sessions can produce objective wiring evidence directly; Claude sessions can only do so by being asked to call the same tools and return raw output.

### 1A.2 Layer 1 — Does It Use Native Tools Naturally on Basic Coding Tasks?

Intent: "Main coding agent" suitability. Throw common coding workflows — file reading / structure analysis / finding regression points / identifying verification commands — and see if native tool selection is natural.

Pass:
- Read/Edit/Bash/Grep/Glob-type selections are natural
- Search → read → analyze flow is smooth
- Does not unnecessarily detour through MCP or recursive `pi` calls

Fail:
- Handles simple file reading through strange detours
- Speaks from memory/guesses without actually reading files

### 1A.3 Layer 2 — Does It Understand the pi-facing MCP Tool Boundary?

Intent: **Prevent tool confusion.** By default, pi custom tools (`entwurf`, `entwurf_resume`, `entwurf_send`, `entwurf_peers`) not being visible is normal — they appear only when the `pi-tools-bridge` MCP adapter is explicitly registered in settings. What matters is "does the session honestly say whether it can see them, and not pretend it can when it can't."

Pass:
- Says tools it cannot see are not visible (e.g., "entwurf tool not visible", "pi custom tools not visible")
- Can explain the boundary between native tools and MCP tools

Fail:
- Pretends to use a tool it cannot see
- Mimics `entwurf` / `entwurf_send` by recursively calling `pi` via `bash`
- Blindly uses only one side when asked about the boundary

Note: check the default visibility boundary together with the operator verification in §8.4, §8.5.

### 1A.4 Layer 3 — Is Focus Maintained as Turns Accumulate?

Intent: Not whether sessions continue, but **whether quality is maintained in a continuing state**. For a single target, inject a fact on the first turn (`entwurf`) (e.g., "Remember 3 core invariants from AGENTS.md, reply with READY only") → continue with `entwurf_resume` on the same taskId 4–5 times, mixing retrieval/exploration/retrieval.

> **Continuation note.** When this layer is run **after §3 + §4 on the same target**, a fresh `entwurf` is no longer available (the bridge enforces uniqueness per target — see §3 operational note). Equivalent procedure: inject the §1A.4 invariants on the **next available turn** (e.g., turn 11) of the same `taskId`, then perform 3–4 more resumes mixing repo exploration (§9) before the recall quiz. The pass criterion is identical — the early-turn injection must survive the intervening exploration.

Pass (post-0.4.1, see strengthened rules above):
- After **8 turns**, holds **3+ early-turn facts** including **one verbatim string injected before turn 5**
- Does not repeat already-done exploration or contradict itself
- Tool selection does not significantly drift as turns progress

Fail:
- Forgets what was read early on immediately
- Produces a tool strategy contradicting a previous turn
- Unnecessarily repeats the same file exploration
- Paraphrases an early-turn fact instead of returning the verbatim string

Note: pi-shell-acp does not implement a post-compaction handoff path. The provider registers a `session_before_compact` handler that cancels every pi-side compaction trigger (silent overflow, threshold, explicit-error overflow, and manual `/compact`). Backend-side auto-compaction is also disabled at launch — Claude Code via `DISABLE_AUTO_COMPACT=1` + `DISABLE_COMPACT=1`, codex-acp via `-c model_auto_compact_token_limit=i64::MAX`. Operators who want pi-side compaction back can set `PI_SHELL_ACP_ALLOW_COMPACTION=1`. For long sessions, the footer percentage shows the backend's own `usage_update.used / size` value, the same signal peer ACP clients (zed, obsidian-agent-client, openclaw-acpx) display. Both supported backends emit per-turn occupancy: claude-agent-acp via `input + output + cache_read + cache_creation` of the last assistant result, codex-acp via `tokens_in_context_window()`. The `[pi-shell-acp:usage] meter=acpUsageUpdate|componentSum source=backend|promptResponse backend=… used=… size=… raw: input=… output=… cacheRead=… cacheWrite=…` diagnostic line carries the per-component breakdown and the meter mode for audit. Use `/clear` (or opt-in `/compact`) when needed.

> **Semantic difference vs native pi.** In pi-shell-acp the footer follows the ACP backend's `usage_update.used / size`, not pi's visible-transcript estimate. This may differ from native pi because the backend counts its own prompt / cache / tool / session state on top of the visible transcript. A small pi conversation can show a large ACP footer; that is a backend overflow-risk signal, not a meter bug. The bridge does not maintain an extra meter sidecar to "correct" this — it surfaces the backend's own number and labels it as such.

### Long-session footer behavior

The footer shows the backend's per-turn occupancy directly. On resumed Claude+ACP sessions where the backend has built up a large `cache_read` payload, the footer will reflect that — `usage_update.used` includes cache tokens, so the percentage tracks what the backend itself reports as "amount of the context window currently consumed." Peer ACP clients render the same value with no extra calibration.

To verify on a real long session:

1. Start a Claude- or Codex-backed session and run any prompt. After the turn completes, check the diagnostic — expect `meter=acpUsageUpdate source=backend` with non-zero `used=…` and `size=…`, plus per-component `raw: …` numbers matching the backend's report.
2. Resume the same session. The first turn after resume should immediately show the backend's current occupancy on the footer (no calibration warm-up needed).
3. Run a tool-only turn that may not trigger a `usage_update` from the backend. The diagnostic should fall through to `meter=componentSum source=promptResponse` and the footer should still have a sensible (component-summed) value. This is expected, not a regression — the meter mode label is the audit surface.
4. Compare the `acpUsageUpdate` footer against any independent backend telemetry (e.g. `claude-agent-acp` stderr, codex-acp logs). They should report the same `used` value.

### 1A.5 Layer 4 — Comparison with Direct Claude Code

> **Prerequisite.** This layer requires a verifier capable of dispatching to **both** the `pi-shell-acp` path and a direct Claude Code path. A verifier already running through `pi-shell-acp` can invoke its sibling via `entwurf`, but cannot dispatch to direct Claude Code through standard MCP tools — Layer 4 therefore requires either a human in the loop or a verifier holding both transport handles. Attempting Layer 4 from inside a single bridged session produces symmetric output, not comparison.

Throw the same questions to both direct Claude Code and the `pi-shell-acp` path (= entwurf target `pi-shell-acp/claude-sonnet-4-6`) and compare. Not string matching, but **semantic-level parity of work quality and tool selection**.

Example comparison questions: summarize the core invariants of this repo / explain the smoke verification system in `run.sh` / why backend auto-compaction is disabled / next 3 improvement points (maintaining thin bridge principle).

Comparison items: latency to first response / native tool selection accuracy / number of unnecessary detours / MCP boundary confusion / quality maintenance around turns 10–15.

Judgment:
- Slightly slower or different phrasing than direct is acceptable
- **Repeated tool confusion, long-turn forgetting, boundary violation workarounds** are a fail

### 1A.6 Result Interpretation

- Layers 0–2 healthy → basic qualifications as a main coding agent are confirmed
- Layer 2 weak → review tool description / MCP visibility explanation / operating contract candidates
- Layer 3 weak → strengthen prompt shape and long-session observation (no in-bridge compaction; rely on pi's manual flow + `[pi-shell-acp:usage]` diagnostic)
- Layer 4 significantly weaker than direct → revisit bridge handoff or capability framing

This questionnaire does not replace smoke.
- Structural/invariant regression: `run.sh` deterministic + smoke
- Main agent suitability: **this section**

---

## 2. Reusing Existing Bench — Check for Major Quality/Performance Anomalies Only

This step is a **rough parity check, not session integrity verification**.

```bash
cd "$REPO_DIR"
PI_BENCH_SUITE=quick ./bench.sh "$PROJECT_DIR"
PI_BENCH_SUITE=full ./bench.sh "$PROJECT_DIR"
```

What to look for:
- Does ACP not act stupidly compared to direct?
- Are read/bash/search/git/sysprompt generally normal?
- Are responses not flying off in completely wrong directions?

Note:
- Do not check exact string matches
- Check **semantic-level parity**
- Passing this bench alone does not prove session continuity

---

## 3. Single-Turn Verification — The First Regression Point to Break

One sync `entwurf` call for the `pi-shell-acp/claude-sonnet-4-6` target.

> **Operational note — `entwurf` uniqueness per (provider, model, session).** The MCP bridge enforces one live `entwurf` per (provider, model) tuple within a verifier session. Strictly speaking §3.1 and §3.2 are two separate single-turn intents, but the second one cannot be a fresh `entwurf` to the same target — it must be the **first `entwurf_resume` of the same `taskId`**. This is operationally fine: §3.1 verifies hook prompt extraction (turn 1), §3.2 verifies tool-call mapping (turn 2 = first resume). Fact injection (§4) then begins from turn 3 onward. If the verifier strictly needs a fresh ACP session for §3.2, run it against a different target (e.g., `claude-opus-4-7` or `gpt-5.2`).

### 3.1 SessionStart Hook Regression Check

Check the `extractPromptBlocks()` regression in `index.ts` first. A single 1-turn that requests only a short answer ("reply with ok only").

Pass:
- `ok` or an equivalently very short response
- Does not mistake hook messages like `device=...`, `time_kst=...` for the main prompt

If broken, suspect: `extractPromptBlocks()` in `index.ts`, the structure where pi hook messages arrive as trailing user messages.

### 3.2 Basic Tool Call Check

A 1-turn like "tell me the current date/time using `date`."

Pass:
- Evidence of running date, or at minimum a tool-based response
- If event-mapper is attached, `[tool:start]`, `[tool:done]`-type notices may be observed

---

## 4. Multi-Turn Verification — Does a Single Target Continue?

This is where it gets important. The execution shape follows §0A — start with a first turn `entwurf(provider="pi-shell-acp", model="claude-sonnet-4-6", mode="sync")`, then continue throwing `entwurf_resume` with the same taskId.

Verification facts follow the §0A wording guide — ban `secret token` / `password` / `API key` types, use only non-sensitive plaintext (code names / colors / animal names, etc.).

### 4.1 Fact Injection → Retrieval → Update

Only the intent of each of the three steps:

1. First turn: inject one non-sensitive fact and receive a short ack (`READY`). E.g., "The password is owl. Reply with READY only, no explanation."
2. Second turn (`entwurf_resume`): retrieve the fact just given. E.g., "What was the password I just told you? Reply in one word only." → `owl`
3. Third turn (`entwurf_resume`): update the fact to a different value and receive `CHANGED`. Retrieve the updated value on the fourth turn.

Pass:
- Second turn answers with the correct value
- Last turn after update answers with the updated value
- Continues naturally without re-throwing a text blob (entwurf orchestration connects via ACP resume/load)

Fail:
- Forgets the fact, or requires the entire first turn content to be re-sent, or the update is not reflected

What to suspect if it looks like Fail:
- If the response is a refusal like "I won't share that" or "I don't know," wording may have triggered safety. Try again with ordinary plaintext following the §0A wording guide — if retrieval still fails, it's a real continuity problem; if retrieval succeeds, it was wording contamination.

---

## 5. Cross-Process Continuity — Does It Continue Across Process Changes?

The `entwurf` → `entwurf_resume` pair from §4 already has **cross-process** character since it goes through different child pi processes. Here we also look at persisted mapping and cache.

### 5.1 Cache Before/After Observation

Run `find "$CACHE_DIR" -maxdepth 1 -type f | sort` twice, before and after §4 execution, and compare.

Pass:
- After the first turn, a persisted session record corresponding to `pi:<sessionId>` is newly created
- The record persists even after the first turn's child pi process exits
- `entwurf_resume` with the same taskId reuses that record as-is to continue the ACP session (continuity maintained)

---

## 6. Persistence Boundary — `cwd:` Sessions Must Never Be Persisted

This is a core invariant of this repo.

With pi routing, `sessionId` is often present, so this verification may directly hit the bridge API.

Record the file count before execution:

```bash
BEFORE=$(find "$CACHE_DIR" -maxdepth 1 -type f | wc -l)
echo "$BEFORE"
```

Direct call:

```bash
cd "$REPO_DIR"
node --input-type=module <<'EOF'
import { ensureBridgeSession, closeBridgeSession, normalizeMcpServers } from './acp-bridge.ts';

const cwd = process.cwd();
const key = `cwd:${cwd}`;
const { hash: mcpServersHash } = normalizeMcpServers(undefined);
const session = await ensureBridgeSession({
  sessionKey: key,
  cwd,
  modelId: 'claude-sonnet-4-6',
  systemPromptAppend: undefined,
  settingSources: ['user'],
  strictMcpConfig: false,
  mcpServers: [],
  bridgeConfigSignature: JSON.stringify({ appendSystemPrompt: false, settingSources: ['user'], strictMcpConfig: false, mcpServersHash }),
  contextMessageSignatures: ['verify:cwd-boundary'],
});
await closeBridgeSession(key, { closeRemote: true, invalidatePersisted: true });
console.log('cwd boundary check done');
EOF
```

Re-check file count after execution:

```bash
AFTER=$(find "$CACHE_DIR" -maxdepth 1 -type f | wc -l)
echo "$AFTER"
```

Expected result:
- `AFTER == BEFORE`
- No new `cwd:`-based record is created

If broken, suspect:
- `isPersistableSessionKey()`
- `persistBridgeSessionRecord()`
- `deletePersistedSessionRecord()`

---

## 7. Ordinary Shutdown Semantics — Process Exit Must Preserve Mappings

After a normal exit, persisted mappings must survive so the next child pi process can pick them up. When the first `entwurf` from §4 finishes, the child pi process exits naturally — the cache record must not be invalidated at that point — this invariant is already observed via the §5.1 snapshot.

If you want to check semantic continuity once more, after the last turn of §4, throw one more `entwurf_resume` with the same taskId after some time and confirm the previous conversation context continues naturally.

Pass:
- Continues from the previous conversation context
- Normal exit does not mean invalidation

Note:
- Currently it's difficult to immediately tell externally whether `resume`, `load`, or `new` was used
- At this document stage, look at **result continuity** first
- Bootstrap path observability is a future improvement point

---

## 8. Tool Call / Event Mapping Verification

### 8.1–8.3 read / grep / bash Character

One sync `entwurf` call each for the `pi-shell-acp/claude-sonnet-4-6` target, with different-intent short task sets: read part of a file and summarize, grep for a specific function definition, current git branch and the latest commit.

Pass:
- Tool usage of read/search/bash character is consistent
- Tool notices appear naturally when needed
- Final responses do not distort tool output

Observation points:
- Is `event-mapper.ts` flowing text/thinking/tool notices appropriately?
- When permission events occur, do they appear at an observable level rather than as strange noise?

### 8.4 pi Custom Tool Visibility Check — Current Key Suspect Point

What we're looking at here is not native tools like `bash`, `read`, `grep`, but **whether pi's custom tools (`entwurf`, `entwurf_resume`, `entwurf_send`, `entwurf_peers` — the narrow set exposed by `mcp/pi-tools-bridge/` as of `035254b`) are visible when going through ACP**.

> **Branching note — which PASS case applies depends on the project's `piShellAcpProvider.mcpServers`.**
>
> - If `piShellAcpProvider.mcpServers` is **empty or omitted** → §8.4 PASS = the spawn replies `entwurf tool not visible` / `pi custom tools not visible`. This is the default contract.
> - If `piShellAcpProvider.mcpServers` **registers `pi-tools-bridge`** (e.g., this repo's own checkout) → §8.4 reduces to honesty check (no hallucination, no overclaim) and §8.5 takes over as the actual visibility verification — the spawn must list precisely those registered servers.
>
> Before running §8.4, verify which case applies:
> ```bash
> jq '.piShellAcpProvider.mcpServers // {} | keys' "$PROJECT_DIR/.pi/settings.json"
> ```
> An empty array (`[]`) means §8.4 strict path. A populated array means §8.5 strict path.

Verification intent: inside the `pi-shell-acp/claude-sonnet-4-6` target, ask "can you see this tool?" and have it reply "not visible" if it cannot. Agreed exact responses:
- Single entwurf visibility: `entwurf tool not visible`
- pi custom tool bundle visibility: `pi custom tools not visible`

**Pass by current design:** the exact agreed strings above.

**Fail:**
- Hallucinates a nonexistent tool as existing
- Mimics entwurf by recursively calling `pi` via `bash`
- Blurs the boundary with "I tried something similar instead"
- Glosses over with only native tools

Current code suspect points:
- `acp-bridge.ts`'s `newSession/loadSession/resumeSession` calls now pass `params.mcpServers`
- That list only comes from `piShellAcpProvider.mcpServers` configuration (§8.5) — no automatic `~/.mcp.json` loading
- `buildSessionMeta()` passes Claude-side `tools: { type: "preset", preset: "claude_code" }`

That is, with the current default (no configuration), **Claude Code native tools are visible but pi custom tools are not** — this is the normal state.

This boundary judgment applies equally to Codex, not just Claude. MCP tool name notation differs between backends — this is a **verified property**, not a guess:
- Claude: `mcp__pi-tools-bridge__entwurf_send` (hyphen)
- Codex: `mcp__pi_tools_bridge__entwurf_send` (underscore)

Empirical confirmation: in self-report tests across both backends (2026-04-27, 2026-04-29 runs in History), `claude-sonnet-4-6` reports the hyphen form and `gpt-5.x` (Codex) reports the underscore form. Verifiers SHOULD check that the bridge prefix appears in the form expected for the active backend, not the other one — a Claude session reporting the underscore form (or a Codex session reporting the hyphen form) is a bridge / backend identification leak, not a typo. Set the verification criterion on whether **bridge name (`pi-tools-bridge` for Claude / `pi_tools_bridge` for Codex) + tool suffix** appear together with the right backend pairing.

> **Two-layer naming — disambiguate before asking.** The bridge identifier has two distinct separator layers, and a sloppy prompt can match either:
>
> - **Outer separator** (between `mcp`, server, and tool name): `__` (double underscore) on **both** backends. Asking "is the separator hyphen or underscore" matches this layer and falsely concludes "match" across backends.
> - **Inner server name** (the part between the outer `__`s): `pi-tools-bridge` on Claude vs `pi_tools_bridge` on Codex. This is the layer §8.4 actually cares about.
>
> Recommended prompt template — ask the agent to print the **literal callable identifier** for a known tool, no transformation:
>
> ```
> Print the exact identifier you would use to call entwurf_peers,
> verbatim, no quoting changes. Pick whichever of these forms is
> actually present in your tool registry:
>   mcp__pi-tools-bridge__entwurf_peers
>   mcp__pi_tools_bridge__entwurf_peers
> ```
>
> Do NOT use:
>
> ```
> Is the namespace separator a hyphen or underscore?
> ```
>
> The bad form is ambiguous between outer `__` and inner `-` / `_` — false-match risk on both sides.

Meaning of this item:
- The default is declared as "Claude-native only"
- pi harness parity only occurs when a **separate MCP adapter** is created and injected via `piShellAcpProvider.mcpServers`
- The bridge only pass-throughs that; it does not have promotion logic inside the repo

If this test fails:
- Do not force Claude to recursively call `pi` via `bash` to imitate entwurf
- First **make a clear judgment of the current bridge's tool exposure boundary**
- If needed, explicitly add an external MCP adapter to `piShellAcpProvider.mcpServers` and verify via §8.5

### 8.5 pi-facing MCP Injection Visibility — Is a Single Explicit Setting Reflected Equally Across resume/load/new?

The sole MCP responsibility of `pi-shell-acp` is: inject the pi-facing MCPs registered in `piShellAcpProvider.mcpServers` equally into all ACP session requests (`newSession` / `resumeSession` / `loadSession`). What this test verifies is not a "general MCP manager" but "does the one MCP that pi actually wants visible appear consistently across all three paths."

Register one experimental pi-facing MCP (e.g., `session-bridge`) in the project settings. For example, `<PROJECT>/.pi/settings.json`:

```jsonc
{
  "piShellAcpProvider": {
    "mcpServers": {
      "session-bridge": {
        "command": "node",
        "args": ["/path/to/consumer-project/mcp/session-bridge/server.js"]
      }
    }
  }
}
```

**Basic visibility (1 turn):**

From the same project, throw a prompt like "list the visible MCP server names separated by commas" to the `pi-shell-acp/claude-sonnet-4-6` target via one sync `entwurf`.

Pass:
- The registered MCP (e.g., `session-bridge`) appears in the response list
- Unregistered MCPs are not visible (confirms no automatic `~/.mcp.json` loading)

**resume/load/new consistency (multi-turn):**

Run two or more turns using the §4 pattern (`entwurf` → same taskId `entwurf_resume`) and confirm the MCP server list seen in each turn is identical.

Pass: The server lists in both responses are identical.
Fail: Only visible in turn 1, or different in turn 2 → session fingerprint or three-path injection consistency issue.

**Config change → session invalidation:**

When `piShellAcpProvider.mcpServers` changes, `bridgeConfigSignature` changes, causing the persisted session to fail compatibility and transition to a new session. Immediately after adding/removing a `mcpServers` entry in settings.json, throw `entwurf_resume` or a new `entwurf` and confirm the new configuration is immediately reflected.

Pass: New configuration reflected immediately (no stale capabilities).

Under the current operational standard, this visibility check is run for **both Claude and Codex**, and at least one bridged MCP tool call is actually passed through. The most stable automation path is a negative-path `entwurf_send` call. If a `No pi control socket ...` error surfaces for a nonexistent target, it means the `ACP host → MCP bridge → pi-side RPC` call path is actually alive.

---

## 9. Scenario Testing — Use It Like an Actual Worker

This step is more important than synthetic benchmarks. One sync `entwurf` call each for a single target (`pi-shell-acp/claude-sonnet-4-6`), with different-intent task sets.

- **9.1 Self-understanding**: read AGENTS.md/README and summarize this repo's current invariants in 7 lines or fewer (provider/model/settings names, session continuity boundary, bootstrap order, what not to do)
- **9.2 Structural explanation**: explain the core structure based on `acp-bridge.ts`, `index.ts`. Use agent-shell as a semantic reference and include things not intentionally brought in
- **9.3 Next improvement proposals**: 3 improvement points that do not break the thin bridge principle. Each item includes reason / files to touch / verification method

Pass:
- Responses maintain the thin bridge philosophy
- Own repo context is understood
- Grounded in actual files without hallucination

---

## 10. Process/Cache Hygiene Verification

### 10.1 Pre-observation

```bash
pgrep -af claude-agent-acp || true
find "$CACHE_DIR" -maxdepth 1 -type f | sort
```

### 10.2 Re-observation After Multiple Tests

```bash
pgrep -af claude-agent-acp || true
find "$CACHE_DIR" -maxdepth 1 -type f | sort
```

Expected results:
- Running many tests does not cause `claude-agent-acp` processes to multiply indefinitely
- Cache records do not explode meaninglessly
- No garbage records unrelated to `pi:<sessionId>` are created

Note:
- An increase in cache file count can be natural when creating new sessions
- What matters is **whether boundaries are maintained** and **whether orphans remain**

### 10.3 Expected `claude-agent-acp` count formula

When checking process hygiene, `BEFORE_ACP` (captured in §1.5) sets the baseline. The bound during verification is:

```
AFTER_ACP ≤ BEFORE_ACP
          + (number of distinct alive
             (sessionKey, backend, modelId, bridgeConfigSignature) tuples
             that this verifier run is currently holding open)
```

This is an **upper bound**, not an equation. Two effects can push `AFTER_ACP` below the prediction:

1. **Child reuse** (`acp-bridge.ts:2340` — `bridgeSessions.get(params.sessionKey)` plus `isSessionCompatible(...)`). A single `entwurf` + N `entwurf_resume` calls on the same `(provider, model)` reuse **one** child for the whole sequence. Delta=0 against `BEFORE_ACP` is the **expected** state when the verifier was already holding that bridge session at snapshot time.
2. **Idle reaping.** Long-idle child processes that no caller is actively holding can exit between snapshots, so `AFTER_ACP` can be **less than** `BEFORE_ACP`. Confirmed empirically — the 2026-04-29 axis-3 reverse run observed `claude-agent-acp` 4 → 2 and `codex-acp` 4 → 3 across the verification window without any explicit close. Both deltas are consistent with reaping plus reuse, not regression.

Settings changes that mutate `bridgeConfigSignature` (`mcpServers`, `tools`, `skillPlugins`, `permissionAllow`, `disallowedTools`, `codexDisabledFeatures`, `appendSystemPrompt`, `settingSources`, `strictMcpConfig`) — or a `(provider, model)` switch — close the existing child and spawn a new one, so they push `AFTER_ACP` up by 1 per switch.

"+1 verifier own" is **not** a separate term. If `BEFORE_ACP` was captured **before** the verifier spawned its first bridge session, the verifier's own child is part of the alive-tuples count above. If `BEFORE_ACP` was captured **after**, the verifier's own child is already in the baseline and not added again. Whichever side it falls on, do not double-count.

`AFTER_ACP > BEFORE_ACP + alive_tuples` is the actionable signal — that means an unexpected child appeared. If that happens, walk the parent chain to identify the source:

```bash
for pid in $(pgrep claude-agent-acp); do
  echo "=== $pid ==="
  ps -o pid,ppid,etime,cmd -p $pid | tail -1
  PARENT=$(ps -o ppid= -p $pid | tr -d ' ')
  ps -o pid,etime,cmd -p $PARENT 2>/dev/null | tail -1
  echo
done
```

A `claude-agent-acp` whose parent `pi` process has already exited is an **orphan** — flag and preserve as evidence (§13). If the parent is alive but does not match any verifier-controlled taskId, it's likely a **prior verification cycle's leftover**; identify and close before continuing.

---

## 11. pi Session Record Check — Is It Usable as a Shared Memory Axis for andenken?

The key is whether **pi session files are maintained as the shared record source** even when using ACP.

After the `entwurf` → `entwurf_resume` pair from §4 finishes, locate the child pi session file for that task (identify location via taskId) and inspect it with `wc -l` / `tail`.

> **Path pattern.** entwurf-spawned child pi sessions are written to:
> ```
> ~/.pi/agent/sessions/--<cwd-encoded>--/<timestamp>_entwurf-<taskId>.jsonl
> ```
> where `<cwd-encoded>` is the entwurf cwd with `/` replaced by `-`. To resolve a `taskId` to its session file in one line:
> ```bash
> ls ~/.pi/agent/sessions/--*--/*_entwurf-<TASK_ID>.jsonl 2>/dev/null
> ```
> A naive `grep -rl <TASK_ID> ~/.pi/agent/sessions/` will also match the **parent** verifier's session (where the verifier quoted the taskId in its own output) — do not analyze that file as the spawn's transcript. Use the path pattern instead.
>
> Schema reminder: `role` is at `.message.role`, not at the top level. To count actual user/assistant turns:
> ```bash
> jq -r '.message.role // .type' "$F" | sort | uniq -c
> ```

Pass:
- user / assistant turns are normally accumulated in the pi session
- The transcript is not broken or empty just because ACP was used
- Minimum session semantics remain for future embedding

Important:
- What we're looking at here is the **pi-side record axis**, not the ACP internal transcript
- What we're preserving is the coexistence of "Claude via ACP, memory via pi axis"

---

## 12. Verification Points Not Yet Covered

The following are documented but observability/automation is still insufficient.

1. Making the actual bootstrap path — whether `resume`, `load`, or `new` — immediately visible externally. Currently only verifiable via stderr `[pi-shell-acp:bootstrap]` lines. In the entwurf orchestration path, that stderr is not surfaced to the front end, making it difficult to immediately answer whether `bridge continuity` passed during failure diagnosis. This lack of observability causes wording contamination to be misdiagnosed as continuity failure (see §0A "bridge vs semantic continuity"). **Current reinforcement path**: `PI_ENTWURF_CHILD_STDERR_LOG` opt-in env mirrors child stderr to a file to automatically verify the S6 (spawn `path=new`) / R4 (resume `path=resume|load`) gate. (This sentinel runner itself lives in the test runner maintained by agent-config as consumer, but spawn authority and registry are owned by this repo. The past agent-config sentinel commit is `9ee39aa`.)
   <br>
   **Verifier one-liner** — to capture bootstrap evidence during a manual VERIFY.md run, export the env before any `entwurf` call and grep the result after:
   ```bash
   export PI_ENTWURF_CHILD_STDERR_LOG=/tmp/pi-shell-acp-verify-stderr.log
   # ... run §3 / §4 / §5 entwurf calls ...
   grep -E '\[pi-shell-acp:(bootstrap|model-switch|cancel|shutdown)\]' \
     "$PI_ENTWURF_CHILD_STDERR_LOG"
   ```
   Without this, §5/§7 can only judge **semantic continuity** — `bridge continuity` (sessionKey/acpSessionId/bootstrap path) remains unverified.

   > **Self-spawn limitation.** This env must be present in the bridge process at startup. If you run VERIFY.md from inside a pi-shell-acp session (verifier already bound to the bridge), `export` from the running shell does **not** propagate into that bridge — restart the parent session with `PI_ENTWURF_CHILD_STDERR_LOG` already exported, or run VERIFY.md from a plain shell that has not yet bound the bridge. This is a known operational corner of replicant-testing-replicant runs (see "Why this document exists" at the top).
2. When persisted session incompatibility occurs, operators reading the invalidation reason quickly
3. ~~Clearly observing the `unstable_setSessionModel` path vs new session fallback path on model switch~~ — see §12.3
4. ~~Observing how cleanly bridge and child process are cleaned up on cancel/abort~~ — see §12.4
5. Checking stream shape stability as tool notices / thinking / text blocks accumulate in long sessions
6. Entwurf-style continuity (see §12.5) — for both Claude and Codex backends, the bridge's resume/load path continues for the same spawn shape as entwurf. Entwurf orchestration itself (which target to spawn for, taskId / async completion / resume identity lock) now lives in this repo's `pi-extensions/entwurf.ts` + `pi/entwurf-targets.json` + `mcp/pi-tools-bridge/`. (Previously owned by agent-config. Migration history in AGENTS.md `§Entwurf Orchestration`.)
7. Separating observability of `bridge continuity` (sessionKey/acpSessionId/bootstrap path) and `semantic continuity` (retrieving previous turn facts) — the two layers can pass/fail independently. The rule is only in §0A, but there's no automated smoke that judges them separately yet.

In other words, this document is not a completion declaration but an **operational document that exposes the next improvement points**.

### 12.3 Model Switch Observability (green)

The `unstable_setSessionModel` path flows a single diagnostic line so operators can read it directly in stderr. Same `key=value` format as bootstrap/cancel lines.

```text
[pi-shell-acp:model-switch] path=bootstrap|reuse outcome=applied|unsupported|failed sessionKey=... backend=... acpSessionId=... fromModel=... toModel=... reason=... fallback=new_session|none
```

Semantics (actual rules, not just observability):

- `path=bootstrap` — the `enforceRequestedSessionModel` path immediately after new/resume/load. If `requestedModelId` is present, enforcement is always attempted. `resolveModelIdFromSessionResponse()` uses requested as fallback when the backend does not return currentModelId, so skipping with "current == requested" judgment is wrong. Here, `outcome=failed` still throws as before and fails the entire bootstrap (fail-fast maintained).
- `path=reuse` — when `modelId` changes in a compatible existing session in `ensureBridgeSession`.
  - `outcome=applied`: `setModel` succeeded, same session maintained
  - `outcome=unsupported fallback=new_session`: `setModel` not a function → `closeBridgeSession` + `startNewBridgeSession`
  - `outcome=failed fallback=new_session reason=...`: `setModel` throws → `closeBridgeSession` + `startNewBridgeSession`
  - Both fallback paths are followed by `[pi-shell-acp:bootstrap] path=new`.

Smoke:

```bash
./run.sh smoke-model-switch /path/to/consumer-project
```

Pass criteria (both Claude/Codex per backend):

- `[pi-shell-acp:model-switch] path=reuse outcome=applied` line exists
- `[pi-shell-acp:model-switch] path=reuse outcome=unsupported fallback=new_session` line exists
- `[pi-shell-acp:model-switch] path=reuse outcome=failed fallback=new_session reason=...` line exists
- After both fallbacks, `[pi-shell-acp:bootstrap] path=new` appears once each, confirming new session reboot actually occurred
- After fallback, a short one-turn prompt with the new session succeeds with `stopReason=end_turn`

The bootstrap branch only adds logging, and deterministic smoke centers on the 3 reuse branches. Bootstrap `unsupported` / `failed` are conservatively maintained as the current operational default (unsupported is skip, failed is throw).

Operational default is resilient (reuse is stderr diagnostic + new-session fallback, pi session continues); smoke is fail-fast (any violation causes total failure).

### 12.4 Cancel / Abort Cleanup Observability (green)

The cancel/abort path flows 3 types of diagnostic lines so operators can read them directly in stderr. Same `key=value` format as bootstrap lines.

```text
[pi-shell-acp:cancel]      sessionKey=... backend=... acpSessionId=... outcome=dispatched|unsupported|failed reason=...
[pi-shell-acp:shutdown]    sessionKey=... backend=... acpSessionId=... closeRemote=... invalidatePersisted=... childPid=... closedRemote=ok|fail|skip childExit=exited|timeout
[pi-shell-acp:orphan-kill] sessionKey=... backend=... pid=... signal=SIGKILL
```

Cleanup invariant (actual rules, not just observability):

- `onAbort` only calls `cancelActivePrompt()` and does not destroy bridge/child (session must remain reusable after abort)
- In the `streamShellAcp` catch block, for `stopReason === "error"` cases (= actual error, not user abort), explicitly clean up with `closeBridgeSession(..., {closeRemote:true, invalidatePersisted:false})`
- `destroyBridgeSession` waits up to 2 seconds for child exit, printing `orphan-kill` line if needed

Smoke:

```bash
./run.sh smoke-cancel /path/to/consumer-project
```

Pass criteria:

- `[pi-shell-acp:cancel]` line is present in stderr
- `outcome=dispatched` or `outcome=unsupported` is normal, `outcome=failed` is a failure
- After abort, the next prompt with the same sessionKey succeeds (session reuse)
- `[pi-shell-acp:shutdown]` line is present
- After explicit `closeBridgeSession`, backend process delta is 0

Operational default is resilient (stderr diagnostic only, pi session continues); smoke is fail-fast (any violation causes total failure).

### 12.5 Entwurf-Style Continuity (bridge-level)

This smoke mimics exactly the spawn form that entwurf actually uses (`pi --mode json -p --no-extensions -e <repo> --provider pi-shell-acp --model <M> --session <F> <task>`) to verify turn1=new → turn2=resume(Claude)/load(Codex) continuity. Evidence is checked both in bridge diagnostic lines (`[pi-shell-acp:bootstrap]`, `[pi-shell-acp:model-switch]`, `[pi-shell-acp:shutdown]`) and in the session file assistant payload.

What this smoke proves is **bridge-level continuity**: "pi-shell-acp can continue sessions via resume/load path for a given (backend, session file, model) combination." **Which target to spawn for / async orchestration / resume identity lock / matrix coverage** is handled by this repo's `pi/entwurf-targets.json` registry and `mcp/pi-tools-bridge` (entwurf orchestration; previously owned by agent-config before migration).

Smoke:

```bash
./run.sh smoke-entwurf-resume /path/to/consumer-project
```

Pass criteria:

- turn1 `[pi-shell-acp:bootstrap] path=new backend=<backend>` line exists + acpSessionId extractable
- turn1 session file has 1 or more `role:"assistant"` records
- turn2 `[pi-shell-acp:bootstrap] path=resume|load backend=<backend>` line exists + acpSessionId matches turn1
- No `bootstrap-invalidate` / `bootstrap-fallback` lines in turn2
- Session file assistant message count ≥ 2 and last assistant payload length > 0

**Scope (retired narrative warning):**

- For both Claude / Codex, the bridge continues sessions in the backend-native way. Claude uses ACP `resumeSession`, Codex uses `loadSession` (codex-acp capability difference — `resumeSession: false, loadSession: true`). This smoke only verifies that the bridge correctly routes both paths.
- This smoke no longer uses labels like "shape-equivalent vs real e2e." That distinction came from a past state where entwurf spawn authority was env-var (`PI_ENTWURF_ACP_FOR_CODEX=1`) based. The current spawn authority is this repo's `pi/entwurf-targets.json` registry, and the bridge does not read the registry. That env var is legacy and will be cleaned up as the registry stabilizes.
- The entire entwurf orchestration (parent × target positive matrix, async completion, resume identity lock) is the responsibility of this repo's entwurf surface (`pi-extensions/entwurf.ts` + `lib/entwurf-core.ts` + `pi/entwurf-targets.json` + `mcp/pi-tools-bridge`). This `smoke-entwurf-resume` only verifies bridge-level continuity — the orchestration gate is handled by `mcp/pi-tools-bridge/test.sh` + `scripts/session-messaging-smoke.sh`.

This smoke is not promoted to `setup` / baseline exit criteria. Maintained only as additional evidence gate.

---

## 13. Evidence to Always Preserve on Failure

When a problem occurs, at minimum preserve the following:

```bash
pgrep -af claude-agent-acp || true
find "$CACHE_DIR" -maxdepth 1 -type f | sort
# resolve taskId(s) to entwurf-child session files (see §11 path pattern)
ls ~/.pi/agent/sessions/--*--/*_entwurf-${TASK_ID}.jsonl 2>/dev/null
# bootstrap evidence (only available if PI_ENTWURF_CHILD_STDERR_LOG was set, §12.1)
[ -n "$PI_ENTWURF_CHILD_STDERR_LOG" ] && \
  grep -E '\[pi-shell-acp:(bootstrap|model-switch|cancel|shutdown)\]' \
    "$PI_ENTWURF_CHILD_STDERR_LOG"
```

Also preserve:
- Exact calls used (entwurf provider/model/mode + entwurf_resume taskId)
- Full stdout/stderr
- Child pi session file path for that task
- Cache directory changes
- Difference between expected and actual results

Short record example:

```text
[verify] multi-turn continuity failed
- call: entwurf(provider="pi-shell-acp", model="claude-sonnet-4-6", mode="sync") → taskId=...
        then entwurf_resume(taskId=..., task="What was the password I just told you? Reply in one word only.")
- injected: "The password is owl. Reply with READY only, no explanation."
- expected: second turn returns "owl"
- actual: model says it does not remember
- cache: persisted file existed
- bridge stderr: [pi-shell-acp:bootstrap] line not captured
- process: no orphan / or orphan 1 left
- wording-recheck: tried again with "The codename is penguin" → still fails (rules out wording contamination)
- suspicion: resume/load path broken or session compatibility gate too strict
```

---

## 14. Pass Criteria

The minimum passing bar is:

1. Smoke passes
2. No major anomalies in bench quick/full
3. Single-turn prompt extraction normal
4. Same `SESSION_FILE` multi-turn continuity normal
5. Cross-process continuity normal
6. `cwd:` persistence boundary normal
7. Tool use / event mapping generally normal
8. No excessive orphan processes / garbage records
9. pi session transcript is usable as a shared memory axis
10. pi-facing MCP injection is reflected only as configured in `piShellAcpProvider.mcpServers`, visibility is identical across resume/load/new paths, sessions are correctly invalidated on config change, and invalid configs fail-fast with `McpServerConfigError`
11. **Identity boundary preservation across backends and machines** — for both Claude and Codex backends, regardless of install path or host, the bridged model honestly identifies the harness as `pi-shell-acp`, names the backend as `claude` or `codex` accordingly, lists the same MCP servers and the same MCP tool function set, presents a **backend-native** (not normalized) tool surface, and uses the correct MCP namespace convention (`pi-tools-bridge` for Claude, `pi_tools_bridge` for Codex). Confabulation about pi internals or cross-backend tool surface contamination is a fail.

Passing all 11 establishes a **release verification floor**, not a full 8-hours-a-day operational guarantee. The floor says: protocol smoke holds, the agent honestly recognizes its environment, no tool surface is normalized away, no cross-backend identity leaks, no orphan processes. What it does **not** say: that a real-day workload (50–100+ turns, tool-heavy bursts, partial MCP failures, auth/version drift over weeks) survives. That guarantee needs L3–L5 evidence — see "Evidence Levels" and "Next experimental directions".

---

## Claims Ledger

Each load-bearing claim this document or its parent docs make, with the highest evidence level reached so far, the current evidence behind it, the blind spot still unaddressed, and the next test that would push it up a rung.

| Claim | Level reached | Current evidence | Remaining blind spot | Next test |
|---|---|---|---|---|
| Bridge identity (`pi-shell-acp`) is recognized correctly across Claude / Codex / multiple hosts | **L1** | History 2026-04-27, 2026-04-29 (both axis-3 directions) | Same prompt carrier on both sides — could share a uniform error | L4: ask a non-bridged direct Claude / Codex the same questions in parallel |
| MCP servers (`pi-tools-bridge` + `session-bridge`) and their 8 tool functions are wired and operational | **L2** | 2026-04-29 reverse run: `entwurf_peers` + `session_info` returned real on-disk payloads | Bridge implementation could be uniformly wrong for both sides | L3: corroborate `controlDir` listing, socket aliveness via `lsof`, session JSONL contents directly from a non-bridge shell |
| Native tool surface stays backend-specific (no normalization) | **L1** | All 4 reports list backend-native tools only; no Claude session reports `apply_patch`, no Codex session reports `Bash` | Could be self-reporting fluency, not actual tool wiring | L2 / L3: invoke a backend-specific tool through the bridge and confirm a backend-specific side effect |
| MCP namespace convention is the agent-visible backend marker (`pi-tools-bridge` for Claude, `pi_tools_bridge` for Codex) | **L1 / L2 mixed** | Self-report (L1) plus literal callable identifier in tool-call notices (L2) | Same as above — could be cosmetic | L3: cross-check with claude-agent-acp / codex-acp source / debug logs |
| Bidirectional cross-vendor entwurf orchestration works | **L2** | 2026-04-29 reverse: Codex spawned Claude via `entwurf`, taskId issued, Claude transcript recovered | Spawn ledger consistency under failure / cancellation not exercised | L3: kill the spawned child mid-run, verify cleanup; L5: 100+ spawns over hours |
| Backend auto-compaction is disabled, fact retention holds across 8+ turns | **L1** | 2026-04-29 intra run: 4 facts across 9 turns, verbatim including a 27-character timestamp string | One run, one length range, one model | L3: examine `usage_update` payloads directly; L5: 50+ turn run with periodic recall |
| `claude-agent-acp` / `codex-acp` child reuse + idle reaping holds within `AFTER ≤ BEFORE + alive_tuples` upper bound | **L2 / L3 partial** | `pgrep` snapshots (`acp-bridge.ts:2340` reuse logic + observed reaping) | No fault-injection or concurrent pressure; orphan parent walk not automated | L3: scripted parent-walk + orphan kill check; L5: parallel verifier sessions stressing the same `(provider, model)` |
| `pi-shell-acp` performs at native or near-native quality on 8-hour-a-day workloads | **NOT YET MEASURED** | Anecdotal operator report only; the official verification surface (this document) has not exercised L4 / L5 | Almost everything that matters at production scale | L4: side-by-side native vs bridged on identical task batches; L5: 2–4 hour soak with fault injection |

When a new claim enters the README, AGENTS.md, or CHANGELOG, add a row here with the level it actually rests on. If a claim cannot find a row at L1 or above, it is narrative, not verified.

---

## Next experimental directions

The current document is healthy at L0–L2. The honest gap is L3 → L5. Three experimental tracks would close that:

### Direction 1 — full 4-cell verifier × subject matrix with L3 corroboration

| Verifier | Subject | Status |
|---|---|---|
| Anthropic | Anthropic | done (L1) |
| Anthropic | Codex | done (L2) |
| Codex | Anthropic | done (L2) |
| Codex | Codex | open (intra-Codex baseline) |

For each cell, record alongside the transcript: raw MCP payload (`entwurf_peers`, `session_info`, plus `entwurf_send` to a known live peer), session JSONL on-disk hash, socket aliveness via `lsof`, `pgrep` baseline+delta, and bridge bootstrap diagnostic (`PI_ENTWURF_CHILD_STDERR_LOG`). That set of signals is L3 per cell.

### Direction 2 — long-haul soak (L5)

A 2–4 hour single-session run with all of the following inside one transcript:

- 50–100 short turns
- periodic verbatim-fact recall every 10–15 turns (drawn from earlier turns)
- tool-heavy bursts (5+ tool calls per turn for several turns in a row)
- compaction stays disabled — verify by `[pi-shell-acp:compaction]` line absence
- usage / footer drift recorded every turn
- mid-run partial failure injection: kill an MCP server, wait, restart, resume — bridge must surface the failure clearly and recover

The output of this run is not a pass/fail bit; it is a transcript that future regression hunts can compare against.

### Direction 3 — direct-native parity panel (L4)

Run the same prompt batch (15–25 prompts spanning self-awareness, tool use, multi-turn fact, refactor, debugging) against:

- `pi-shell-acp/claude-sonnet-4-6`
- direct Claude Code (no bridge)
- `pi-shell-acp/gpt-5.4`
- direct Codex (no bridge)

Quality scoring stays semantic, not string-equality. Pass = bridged path's quality is within the run-to-run noise of the matching direct path. This is the only test that can actually back the claim "pi-shell-acp is native-quality".

These three directions are the load-bearing experiments for any claim about real-world operational quality. Until they have been run, narrative in this repo (and downstream READMEs) should not promise more than the floor in §14.

---

## Diversifying the verifier matrix

| Verifier | Subject | What it adds | Status |
|---|---|---|---|
| `pi-shell-acp/claude-opus-4-7` | `pi-shell-acp/claude-sonnet-4-6` | intra-Anthropic baseline | done (History 2026-04-27, 2026-04-29) |
| `pi-shell-acp/claude-opus-4-7` (local) | `pi-shell-acp/gpt-5.x` (Oracle, Codex) | cross-vendor: Anthropic verifier × Codex subject through the same bridge, across hosts | done (History 2026-04-29 axis-3) |
| `pi-shell-acp/gpt-5.x` | `pi-shell-acp/claude-sonnet-4-6` | cross-vendor reverse: Codex verifier × Claude subject — closes the echo-chamber risk via objective MCP tool calls + reverse-direction orchestration | done (History 2026-04-29 axis-3 reverse) |
| `pi-shell-acp/gpt-5.4` | `pi-shell-acp/gpt-5.5` | intra-Codex baseline | open (marginal value — both axis-3 directions closed) |

Cross-vendor cells are the most informative: the bridge's `developer_instructions` carrier on the Codex side and `_meta.systemPrompt` carrier on the Claude side are structurally different, so a Codex verifier and a Claude subject (or vice versa) exercise both carriers in one run. If they agree on what they see — same MCP servers, same tool boundary, same operator-config isolation — the carrier divergence is invisible to the agents, which is the bridge's identity-isolation goal made empirically visible.

The §1A.4 long-turn fact retention bar (8 turns / 3+ facts / verbatim) holds across vendors — both backends have backend auto-compaction disabled, so neither side has a different excuse for forgetting.

What the cross-vendor samples (Codex on Oracle 2026-04-29, plus the reverse-direction run later that day) confirmed beyond intra-Anthropic runs:

- **Bridge identity is backend-invariant.** Both Claude and Codex self-report `pi-shell-acp` as the harness and enumerate the same two MCP servers (`pi-tools-bridge` + `session-bridge`) and the same eight MCP tool functions. Whatever distortion the bridge could introduce is empirically not introduced.
- **Native tool surface is correctly backend-specific.** Claude reports `Bash/Read/Edit/Write/Skill`; Codex reports `exec_command/write_stdin/apply_patch/update_plan/request_user_input/list_mcp_resources/read_mcp_resource/multi_tool_use.parallel`. Neither side hallucinates the other's native tools — the bridge does not normalize the tool surface, which is the §0 thin-bridge invariant in operation.
- **MCP namespace convention difference is the agent-visible boundary marker** (§8.4 verified property). A Claude session reporting underscore form, or a Codex session reporting hyphen form, would be a backend-identity leak. The §8.4 "two-layer naming" note disambiguates the outer `__` separator (same on both backends) from the inner server name (`pi-tools-bridge` vs `pi_tools_bridge` — the actual marker).
- **Prompt-only echo-chamber risk closed by objective MCP tool calls; shared-infrastructure blind spots remain.** A pile of self-reports could in principle agree on a hallucinated bridge if the bridge were transmitting its own hallucination uniformly through the prompt layer. The 2026-04-29 reverse-direction run resolved that prompt-layer concern: Codex called `mcp__pi_tools_bridge__entwurf_peers` and `mcp__session_bridge__session_info` directly and got back real `controlDir` / `sessionId` / `socketPath` payloads matching on-disk state. What is **not** closed: the verifier still relies on the same MCP bridge implementation, same on-disk state, and same operator-config overlay as the subject — uniform corruption of those layers would survive this test. Closing those blind spots needs L3 (independent on-disk / process corroboration) and L5 (long-haul soak with fault injection); see "Evidence Levels" and "Next experimental directions" below.
- **Bidirectional cross-vendor orchestration works.** Codex spawned Claude via `entwurf` (axis-3 reverse) — taskId issued, Claude self-report returned, Codex parsed it into its own comparison table. The bridge's entwurf surface is symmetric across vendors, not just protocol-correct.

## History

A log of who ran this document end-to-end and what they changed. Each entry records: date, verifier identity (provider/model orchestrating the run), subject target(s) actually exercised, and a one-line summary of doc upgrades applied as a result.

| Date | Verifier (orchestrator) | Subject target(s) | Notes |
|------|-------------------------|-------------------|-------|
| 2026-04-27 | pi-shell-acp / claude-opus-4-7 | pi-shell-acp / claude-sonnet-4-6 (1 target × 14 turns) | First full pass by an ACP-routed Claude (previously native gpt-5.x territory). Applied A–H upgrades: §3 entwurf-uniqueness operational note, §1.5 pre-verification snapshot block, §1A.4 in-session continuation note, §8.4 mcpServers branching note, §10.3 expected `claude-agent-acp` count formula + parent-walk recipe, §11 entwurf session file path pattern + `.message.role` schema reminder, §12.1 `PI_ENTWURF_CHILD_STDERR_LOG` verifier one-liner, §13 taskId→session-file helper. §3 / §4 / §5 / §6 / §7 / §8.4 / §8.5 / §9 / §11 / §1A.1–1A.4 all PASS. §10 borderline (3 `claude-agent-acp` for 14 turns / 1 spawn — bounded but more than the formula predicts; flagged as observation). |
| 2026-04-29 | pi-shell-acp / claude-opus-4-7 | pi-shell-acp / claude-sonnet-4-6 (1 target × 10 turns, post-0.4.1) | Replicant-testing-replicant run against post-0.4.1 entwurf surface. §3.1 / §3.2 / §4.1 / §5.1 / §8.5 / §1A.1 / §1A.4 / §11 ALL PASS. §1A.4 held 4 facts across 9 turns at glyph-level fidelity (Wed Apr 29 03:35:17 PM KST 2026 returned verbatim from turn 2). §10 process delta=0 against `BEFORE_ACP=4` — under previous formula's prediction of 6, which led to formula re-derivation: bridge reuses one child per `(sessionKey, backend, modelId, bridgeConfigSignature)` tuple, not per entwurf taskId (`acp-bridge.ts:2340`). Doc upgrades: top-of-document "Why this document exists / Strengthened verification rules" (replicant-pair semantics + 4 hardened rules), §1.6 turn map, §1A.4 8-turn / 3-fact / verbatim bar, §1A.5 dual-transport prerequisite, §10.3 formula re-derivation, §12.1 self-spawn limitation note, §1A.5 → "Diversifying the verifier matrix" section above pointing at next cross-vendor cells. Two ACP-routed identities (verifier opus, subject sonnet) describing the same harness in the same words — strongest cross-validation evidence the bridge has produced so far. |
| 2026-04-29 (axis-3) | pi-shell-acp / claude-opus-4-7 (local) | pi-shell-acp / gpt-5.x (Oracle, Codex backend) | **First cross-vendor sample.** Operator installed 0.4.1 on Oracle, ran identity interview against the Codex backend, then a separate Opus session analyzed the Codex self-report. Result: bridge identity (`pi-shell-acp`) and MCP surface (`pi-tools-bridge` + `session-bridge`, 8 tool functions) reported identically across both backends and both hosts; native tool surfaces are correctly backend-specific (Claude `Bash/Read/Edit/Write/Skill` vs Codex `exec_command/apply_patch/update_plan/...`); MCP namespace convention `pi-tools-bridge` vs `pi_tools_bridge` is the agent-visible backend marker (§8.4 verified property). Codex side carries `list_mcp_resources` / `read_mcp_resource` natively — sharper introspection layer than Claude on this same bridge (§1A.1.1 adds an objective-check axis for Codex sessions). Doc upgrades: §1.7 cross-install / cross-backend parity (3 axes), §1A.1.1 Codex objective check (initial draft, superseded same-day — see next row), §8.4 naming difference promoted from "may differ" to "verified property" with empirical confirmation, §14 pass criterion 11 — Identity boundary preservation across backends and machines. The matrix's cross-vendor cell (Anthropic verifier × Codex subject) is now closed; the reverse (Codex verifier × Claude/Codex subject) remains open. |
| 2026-04-29 (axis-3 reverse) | pi-shell-acp / gpt-5.4 (Codex orchestrator) | pi-shell-acp / claude-sonnet-4-6 (Claude subject, spawned via entwurf) + direct MCP tool calls on `pi-tools-bridge` and `session-bridge` | **Prompt-only echo-chamber risk closed (L2 reached).** The same Opus verifier from the previous row delegated the next step to a Codex orchestrator, which (a) called `mcp__pi_tools_bridge__entwurf_peers` and `mcp__session_bridge__session_info` directly and received real on-disk payloads (`controlDir`, `sessionId`, `socketPath`, `Session Name=pi-shell-acp`), (b) spawned a Claude sibling via `entwurf` and recovered its self-report, then (c) wrote its own cross-vendor comparison table satisfying §14 pass criterion 11. The previous §1A.1.1 draft assumed `list_mcp_resources` would return the MCP-server registry, but it actually reports MCP-server *resources* (data records); pi-tools-bridge and session-bridge expose tools only, not resources, so it returns `{"resources":[]}` correctly. §1A.1.1 was rewritten to use the working recipe (`entwurf_peers` + `session_info` direct calls). Process hygiene observation: `claude-agent-acp` 4 → 2 and `codex-acp` 4 → 3 across the run, no orphans, all entwurf children exited cleanly — §10.3 reformulated as an upper bound (`AFTER ≤ BEFORE + alive_tuples`) to admit child reuse and idle reaping. §8.4 gained a two-layer disambiguation note (outer `__` separator vs inner server-name string — earlier prompts could match either layer and false-conclude "match"). §1.7 axis-3 evidence note added that bidirectional orchestration works (Codex → Claude entwurf, taskId 857481de). Both axis-3 directions in the matrix are now done; intra-Codex baseline remains open with marginal added value. |
