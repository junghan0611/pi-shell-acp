# VERIFY.md

Manual verification guide for `pi-shell-acp`.

This document is a **working document, not a metrics document**.
Even if scripts break, an agent that follows these steps and reads the results should be able to immediately determine:

- Whether ACP is broken in single-turn mode
- Whether multi-turn sessions are genuinely continuing
- Whether cross-process continuity is working
- Whether bridge invariants are not leaking
- Whether tool call / event mapping is visible
- Whether processes/cache are not left behind as garbage
- Whether pi session records are usable as a shared memory axis for andenken embedding

---

## 0A. Execution Policy — Transparent Mode (Real-World Baseline)

The verification in this document is not a benchmark. In production, we continuously exchange **short sync turns** like `delegate` / `delegate_resume` to check state, and stop immediately to isolate the cause before resuming when something looks off.

This document records only **verification intent (what we're looking at) and pass criteria (how to judge)**. The execution shape is determined by the agent using the most reasonable tools in its environment. The same intent can be verified in different ways — as long as the pass criteria are met.

### Default Execution Shape — delegate orchestration

- Single-turn verification: one `delegate(provider="pi-shell-acp", model="<M>", mode="sync")` call
- Multi-turn verification: first turn via `delegate`, subsequent turns via `delegate_resume` with the same `taskId`
- Different backend verification: same pattern with only provider/model changed (e.g., `pi-shell-acp/codex-...`)

### What NOT to Do — Bypassing the Operational Path

The following patterns **bypass the delegation logic itself** that we're trying to verify. Even if continuity appears to hold on the surface, these are not the real operational path (delegate → delegate_resume), so passing does not mean production is healthy.

- ✗ Creating session files directly with `mktemp /tmp/pi-shell-acp-verify-XXXXXX.jsonl`
- ✗ Manual calls of the form `pi -e <REPO> --session <FILE> --model <M> -p '...'`
- ✗ Faking multi-turn by passing the same session file twice

In the past, having these commands written out directly caused agents to copy them verbatim and bypass the operational path. This document contains only intent and pass criteria. Shell commands are retained only where they are integral to the verification, such as boundary checks (§6).

The manual `pi --session` path is only used in two cases:
- When the delegate path itself is broken and an isolated debug bypass is needed
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

### 1.1 Variables

```bash
export REPO_DIR=/path/to/pi-shell-acp
export PROJECT_DIR=/path/to/consumer-project
export CACHE_DIR=$HOME/.pi/agent/cache/pi-shell-acp/sessions
mkdir -p "$CACHE_DIR"
```

### 1.2 Install / Smoke

To verify from an actual consumer project:

```bash
cd "$REPO_DIR"
./run.sh setup "$PROJECT_DIR"
```

Quick re-verification:

```bash
cd "$REPO_DIR"
npm run typecheck
npm run check-mcp            # pi-facing MCP normalization pure-logic gate (no Claude/ACP subprocess)
./run.sh smoke "$PROJECT_DIR"
```

Expected results:
- typecheck passes
- check-mcp passes (`[check-mcp] N assertions ok`)
- `--list-models pi-shell-acp` succeeds
- bridge prompt smoke succeeds

---

## 1A. Main Agent Evaluation — Is `pi-shell-acp` Claude Strong Enough?

This section moves the evaluation questionnaire from the llmlog into this repo's operational document.
The core question is one:

> **When Claude is connected through pi via ACP, is it strong enough as the main coding agent?**

This evaluation is separate from the continuity smoke. If smoke proves "sessions continue," this questionnaire examines **tool self-awareness / native tool usability / pi-facing MCP boundary awareness / long-turn focus / quality relative to direct Claude Code**.

The execution shape follows §0A — Layers 0–3 start with one `delegate` for a single target (`pi-shell-acp/claude-sonnet-4-6`) and continue via `delegate_resume` with the same taskId for multi-turn. Layer 4 is a comparison with direct Claude Code, so it uses a separate path.

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

Intent: **Prevent tool confusion.** By default, pi custom tools (`delegate`, `delegate_resume`, `send_to_session`, `list_sessions`) not being visible is normal — they appear only when the `pi-tools-bridge` MCP adapter is explicitly registered in settings. What matters is "does the session honestly say whether it can see them, and not pretend it can when it can't."

Pass:
- Says tools it cannot see are not visible (e.g., "delegate tool not visible", "pi custom tools not visible")
- Can explain the boundary between native tools and MCP tools

Fail:
- Pretends to use a tool it cannot see
- Mimics `delegate` / `send_to_session` by recursively calling `pi` via `bash`
- Blindly uses only one side when asked about the boundary

Note: check the default visibility boundary together with the operator verification in §8.4, §8.5.

### 1A.4 Layer 3 — Is Focus Maintained as Turns Accumulate?

Intent: Not whether sessions continue, but **whether quality is maintained in a continuing state**. For a single target, inject a fact on the first turn (`delegate`) (e.g., "Remember 3 core invariants from AGENTS.md, reply with READY only") → continue with `delegate_resume` on the same taskId 4–5 times, mixing retrieval/exploration/retrieval.

Pass:
- Still holds onto the initial invariants and intermediate exploration results after 5 turns
- Does not repeat already-done exploration or contradict itself
- Tool selection does not significantly drift as turns progress

Fail:
- Forgets what was read early on immediately
- Produces a tool strategy contradicting a previous turn
- Unnecessarily repeats the same file exploration

Note: compaction handoff itself is verified separately via `./run.sh check-compaction-handoff`, `./run.sh smoke-compaction "$PROJECT_DIR"`.

### 1A.5 Layer 4 — Comparison with Direct Claude Code

Throw the same questions to both direct Claude Code and the `pi-shell-acp` path (= delegate target `pi-shell-acp/claude-sonnet-4-6`) and compare. Not string matching, but **semantic-level parity of work quality and tool selection**.

Example comparison questions: summarize the core invariants of this repo / explain the smoke verification system in `run.sh` / why compaction handoff is needed / next 3 improvement points (maintaining thin bridge principle).

Comparison items: latency to first response / native tool selection accuracy / number of unnecessary detours / MCP boundary confusion / quality maintenance around turns 10–15.

Judgment:
- Slightly slower or different phrasing than direct is acceptable
- **Repeated tool confusion, long-turn forgetting, boundary violation workarounds** are a fail

### 1A.6 Result Interpretation

- Layers 0–2 healthy → basic qualifications as a main coding agent are confirmed
- Layer 2 weak → review tool description / MCP visibility explanation / operating contract candidates
- Layer 3 weak → strengthen compaction, prompt shape, long-session observation
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

One sync `delegate` call for the `pi-shell-acp/claude-sonnet-4-6` target.

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

This is where it gets important. The execution shape follows §0A — start with a first turn `delegate(provider="pi-shell-acp", model="claude-sonnet-4-6", mode="sync")`, then continue throwing `delegate_resume` with the same taskId.

Verification facts follow the §0A wording guide — ban `secret token` / `password` / `API key` types, use only non-sensitive plaintext (code names / colors / animal names, etc.).

### 4.1 Fact Injection → Retrieval → Update

Only the intent of each of the three steps:

1. First turn: inject one non-sensitive fact and receive a short ack (`READY`). E.g., "The password is owl. Reply with READY only, no explanation."
2. Second turn (`delegate_resume`): retrieve the fact just given. E.g., "What was the password I just told you? Reply in one word only." → `owl`
3. Third turn (`delegate_resume`): update the fact to a different value and receive `CHANGED`. Retrieve the updated value on the fourth turn.

Pass:
- Second turn answers with the correct value
- Last turn after update answers with the updated value
- Continues naturally without re-throwing a text blob (delegate orchestration connects via ACP resume/load)

Fail:
- Forgets the fact, or requires the entire first turn content to be re-sent, or the update is not reflected

What to suspect if it looks like Fail:
- If the response is a refusal like "I won't share that" or "I don't know," wording may have triggered safety. Try again with ordinary plaintext following the §0A wording guide — if retrieval still fails, it's a real continuity problem; if retrieval succeeds, it was wording contamination.

---

## 5. Cross-Process Continuity — Does It Continue Across Process Changes?

The `delegate` → `delegate_resume` pair from §4 already has **cross-process** character since it goes through different child pi processes. Here we also look at persisted mapping and cache.

### 5.1 Cache Before/After Observation

Run `find "$CACHE_DIR" -maxdepth 1 -type f | sort` twice, before and after §4 execution, and compare.

Pass:
- After the first turn, a persisted session record corresponding to `pi:<sessionId>` is newly created
- The record persists even after the first turn's child pi process exits
- `delegate_resume` with the same taskId reuses that record as-is to continue the ACP session (continuity maintained)

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

After a normal exit, persisted mappings must survive so the next child pi process can pick them up. When the first `delegate` from §4 finishes, the child pi process exits naturally — the cache record must not be invalidated at that point — this invariant is already observed via the §5.1 snapshot.

If you want to check semantic continuity once more, after the last turn of §4, throw one more `delegate_resume` with the same taskId after some time and confirm the previous conversation context continues naturally.

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

One sync `delegate` call each for the `pi-shell-acp/claude-sonnet-4-6` target, with different-intent short task sets: read part of a file and summarize, grep for a specific function definition, current git branch and the latest commit.

Pass:
- Tool usage of read/search/bash character is consistent
- Tool notices appear naturally when needed
- Final responses do not distort tool output

Observation points:
- Is `event-mapper.ts` flowing text/thinking/tool notices appropriately?
- When permission events occur, do they appear at an observable level rather than as strange noise?

### 8.4 pi Custom Tool Visibility Check — Current Key Suspect Point

What we're looking at here is not native tools like `bash`, `read`, `grep`, but **whether pi's custom tools (`delegate`, `delegate_resume`, `send_to_session`, `list_sessions` — the narrow set exposed by `mcp/pi-tools-bridge/` as of `035254b`) are visible when going through ACP**.

Verification intent: inside the `pi-shell-acp/claude-sonnet-4-6` target, ask "can you see this tool?" and have it reply "not visible" if it cannot. Agreed exact responses:
- Single delegate visibility: `delegate tool not visible`
- pi custom tool bundle visibility: `pi custom tools not visible`

**Pass by current design:** the exact agreed strings above.

**Fail:**
- Hallucinates a nonexistent tool as existing
- Mimics delegate by recursively calling `pi` via `bash`
- Blurs the boundary with "I tried something similar instead"
- Glosses over with only native tools

Current code suspect points:
- `acp-bridge.ts`'s `newSession/loadSession/resumeSession` calls now pass `params.mcpServers`
- That list only comes from `piShellAcpProvider.mcpServers` configuration (§8.5) — no automatic `~/.mcp.json` loading
- `buildSessionMeta()` passes Claude-side `tools: { type: "preset", preset: "claude_code" }`

That is, with the current default (no configuration), **Claude Code native tools are visible but pi custom tools are not** — this is the normal state.

This boundary judgment applies equally to Codex, not just Claude. However, MCP tool name notation may differ slightly between backends.
- Claude example: `mcp__pi-tools-bridge__send_to_session`
- Codex example: `mcp__pi_tools_bridge__send_to_session`

Therefore, it's safer to set the verification criterion on whether **bridge name (`pi-tools-bridge` / `pi_tools_bridge`) + tool suffix** appear together.

Meaning of this item:
- The default is declared as "Claude-native only"
- pi harness parity only occurs when a **separate MCP adapter** is created and injected via `piShellAcpProvider.mcpServers`
- The bridge only pass-throughs that; it does not have promotion logic inside the repo

If this test fails:
- Do not force Claude to recursively call `pi` via `bash` to imitate delegate
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

From the same project, throw a prompt like "list the visible MCP server names separated by commas" to the `pi-shell-acp/claude-sonnet-4-6` target via one sync `delegate`.

Pass:
- The registered MCP (e.g., `session-bridge`) appears in the response list
- Unregistered MCPs are not visible (confirms no automatic `~/.mcp.json` loading)

**resume/load/new consistency (multi-turn):**

Run two or more turns using the §4 pattern (`delegate` → same taskId `delegate_resume`) and confirm the MCP server list seen in each turn is identical.

Pass: The server lists in both responses are identical.
Fail: Only visible in turn 1, or different in turn 2 → session fingerprint or three-path injection consistency issue.

**Config change → session invalidation:**

When `piShellAcpProvider.mcpServers` changes, `bridgeConfigSignature` changes, causing the persisted session to fail compatibility and transition to a new session. Immediately after adding/removing a `mcpServers` entry in settings.json, throw `delegate_resume` or a new `delegate` and confirm the new configuration is immediately reflected.

Pass: New configuration reflected immediately (no stale capabilities).

Under the current operational standard, this visibility check is run for **both Claude and Codex**, and at least one bridged MCP tool call is actually passed through. The most stable automation path is a negative-path `send_to_session` call. If a `No pi control socket ...` error surfaces for a nonexistent target, it means the `ACP host → MCP bridge → pi-side RPC` call path is actually alive.

---

## 9. Scenario Testing — Use It Like an Actual Worker

This step is more important than synthetic benchmarks. One sync `delegate` call each for a single target (`pi-shell-acp/claude-sonnet-4-6`), with different-intent task sets.

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

---

## 11. pi Session Record Check — Is It Usable as a Shared Memory Axis for andenken?

The key is whether **pi session files are maintained as the shared record source** even when using ACP.

After the `delegate` → `delegate_resume` pair from §4 finishes, locate the child pi session file for that task (identify location via taskId) and inspect it with `wc -l` / `tail`.

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

1. Making the actual bootstrap path — whether `resume`, `load`, or `new` — immediately visible externally. Currently only verifiable via stderr `[pi-shell-acp:bootstrap]` lines. In the delegate orchestration path, that stderr is not surfaced to the front end, making it difficult to immediately answer whether `bridge continuity` passed during failure diagnosis. This lack of observability causes wording contamination to be misdiagnosed as continuity failure (see §0A "bridge vs semantic continuity"). **Current reinforcement path**: `PI_DELEGATE_CHILD_STDERR_LOG` opt-in env mirrors child stderr to a file to automatically verify the S6 (spawn `path=new`) / R4 (resume `path=resume|load`) gate. (This sentinel runner itself lives in the test runner maintained by agent-config as consumer, but spawn authority and registry are owned by this repo. The past agent-config sentinel commit is `9ee39aa`.)
2. When persisted session incompatibility occurs, operators reading the invalidation reason quickly
3. ~~Clearly observing the `unstable_setSessionModel` path vs new session fallback path on model switch~~ — see §12.3
4. ~~Observing how cleanly bridge and child process are cleaned up on cancel/abort~~ — see §12.4
5. Checking stream shape stability as tool notices / thinking / text blocks accumulate in long sessions
6. Delegate-style continuity (see §12.5) — for both Claude and Codex backends, the bridge's resume/load path continues for the same spawn shape as delegate. Delegate orchestration itself (which target to spawn for, taskId / async completion / resume identity lock) now lives in this repo's `pi-extensions/delegate.ts` + `pi/delegate-targets.json` + `mcp/pi-tools-bridge/`. (Previously owned by agent-config. Migration history in AGENTS.md `§Entwurf Orchestration`.)
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

### 12.5 Delegate-Style Continuity (bridge-level)

This smoke mimics exactly the spawn form that delegate actually uses (`pi --mode json -p --no-extensions -e <repo> --provider pi-shell-acp --model <M> --session <F> <task>`) to verify turn1=new → turn2=resume(Claude)/load(Codex) continuity. Evidence is checked both in bridge diagnostic lines (`[pi-shell-acp:bootstrap]`, `[pi-shell-acp:model-switch]`, `[pi-shell-acp:shutdown]`) and in the session file assistant payload.

What this smoke proves is **bridge-level continuity**: "pi-shell-acp can continue sessions via resume/load path for a given (backend, session file, model) combination." **Which target to spawn for / async orchestration / resume identity lock / matrix coverage** is handled by this repo's `pi/delegate-targets.json` registry and `mcp/pi-tools-bridge` (entwurf orchestration; previously owned by agent-config before migration).

Smoke:

```bash
./run.sh smoke-delegate-resume /path/to/consumer-project
```

Pass criteria:

- turn1 `[pi-shell-acp:bootstrap] path=new backend=<backend>` line exists + acpSessionId extractable
- turn1 session file has 1 or more `role:"assistant"` records
- turn2 `[pi-shell-acp:bootstrap] path=resume|load backend=<backend>` line exists + acpSessionId matches turn1
- No `bootstrap-invalidate` / `bootstrap-fallback` lines in turn2
- Session file assistant message count ≥ 2 and last assistant payload length > 0

**Scope (retired narrative warning):**

- For both Claude / Codex, the bridge continues sessions in the backend-native way. Claude uses ACP `resumeSession`, Codex uses `loadSession` (codex-acp capability difference — `resumeSession: false, loadSession: true`). This smoke only verifies that the bridge correctly routes both paths.
- This smoke no longer uses labels like "shape-equivalent vs real e2e." That distinction came from a past state where delegate spawn authority was env-var (`PI_DELEGATE_ACP_FOR_CODEX=1`) based. The current spawn authority is this repo's `pi/delegate-targets.json` registry, and the bridge does not read the registry. That env var is legacy and will be cleaned up as the registry stabilizes.
- The entire delegate orchestration (parent × target positive matrix, async completion, resume identity lock) is the responsibility of this repo's entwurf surface (`pi-extensions/delegate.ts` + `lib/delegate-core.ts` + `pi/delegate-targets.json` + `mcp/pi-tools-bridge`). This `smoke-delegate-resume` only verifies bridge-level continuity — the orchestration gate is handled by `mcp/pi-tools-bridge/test.sh` + `scripts/session-messaging-smoke.sh`.

This smoke is not promoted to `setup` / baseline exit criteria. Maintained only as additional evidence gate.

---

## 13. Evidence to Always Preserve on Failure

When a problem occurs, at minimum preserve the following:

```bash
pgrep -af claude-agent-acp || true
find "$CACHE_DIR" -maxdepth 1 -type f | sort
```

Also preserve:
- Exact calls used (delegate provider/model/mode + delegate_resume taskId)
- Full stdout/stderr
- Child pi session file path for that task
- Cache directory changes
- Difference between expected and actual results

Short record example:

```text
[verify] multi-turn continuity failed
- call: delegate(provider="pi-shell-acp", model="claude-sonnet-4-6", mode="sync") → taskId=...
        then delegate_resume(taskId=..., task="What was the password I just told you? Reply in one word only.")
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

When these 10 pass, `pi-shell-acp` is considered not just an experiment but an **operationally viable ACP bridge within the pi harness**.
