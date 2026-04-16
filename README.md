# pi-shell-acp

> **🔄 REACTIVATED** — This repository is active again as of 2026-04-15.
> It had been archived after the ben approach looked simpler, but that path is now disabled by default in `agent-config` pending account-risk observation.
> The ACP bridge is therefore back as the active Claude path in pi.

![Demo](screenshot.png)

## Status

**Phase:** Active again. ACP bridge is back in service.

**What was built:**

```text
pi
  -> pi-shell-acp          (this repository; thin ACP client)
    -> claude-agent-acp    (canonical ACP server for Claude Code)
      -> Claude Code
        -> native Claude configuration
        -> native MCP configuration
        -> ~/.claude/CLAUDE.md / ~/.claude/skills
        -> CLI / PATH tools
```

**Alternative path (currently disabled by default):**

```text
pi
  -> anthropic provider (direct API, built into pi)
    -> pi-claude-code-use (ben's package; patches Claude Code capabilities)
    -> Claude API
```

The ben approach won because:
- No intermediate process (ACP subprocess) to manage
- No session state synchronization between two runtimes
- pi already owns tool execution — delegating back to Claude Code was redundant
- Simpler debugging, faster response, fewer failure modes

## Benchmark Snapshot (Final)

Benchmark as of **2026-04-10** — the ACP bridge reached competitive parity with direct API routes.
This validated the architecture but also showed that the extra complexity wasn't buying enough.

Comparison used:

- direct: `github-copilot/claude-sonnet-4.6`
- ACP bridge: `claude-agent-sdk/claude-sonnet-4-6`
- harness: real pi project context via `./bench.sh .`

| Test | Direct | ACP bridge | Ratio | Verdict |
|------|--------|------------|-------|---------|
| simple | 3.8s | 4.1s | 1.1x | parity |
| reasoning | 16.5s | 14.8s | 0.9x | bridge faster |
| korean-long | 12.3s | 8.1s | 0.7x | bridge faster |
| tool-read | 8.9s | 8.2s | 0.9x | parity |
| tool-bash | 11.9s | 7.0s | 0.6x | bridge faster |
| multi-step | 10.3s | 8.2s | 0.8x | bridge faster |
| file-search | 11.8s | 8.5s | 0.7x | bridge faster |
| sysprompt | 5.7s | 6.7s | 1.2x | parity |
| code-read | 15.6s | 18.4s | 1.2x | direct slightly faster |
| git-status | 9.1s | 6.4s | 0.7x | bridge faster |

The bridge worked — tool use, reasoning, Korean generation, system prompt adherence all passed.
But "it works" wasn't enough to justify the architectural overhead vs the simpler ben path.

---

## History

### 2026-04-09 - The direct bridge started to collapse under bespoke glue

This repository began as a fork of the original `claude-agent-sdk-pi` approach: use the Claude Agent SDK directly inside a pi provider, block tool execution inside Claude Code, and let pi execute tools itself.

That approach looked attractive because it appeared to preserve pi-native control over tools, sessions, and UI. In practice, it accumulated too much custom glue:

- tool name mapping
- tool argument rewriting
- prompt reconstruction
- session emulation
- tool call ID normalization
- context recovery / ledger logic
- custom MCP exposure for pi tools
- provider-side compensation for SDK behavior changes

The result was not "Claude is weak." The result was that the bridge itself became a parallel state machine.

That showed up as concrete failures:

- repeated or duplicated assistant output
- edit failures caused by argument-shape drift
- context contamination from recovered tool results
- unstable behavior whenever upstream SDK semantics shifted

### 2026-04-09 - Stabilization pass on the old architecture

Before changing architecture, this fork applied a short stabilization pass to confirm the immediate failure modes:

- fixed the `edit` argument mapping to pi's `edits[]` shape
- disabled the ToolWatch ledger that re-injected stale tool results
- added a module re-registration guard to prevent provider overwrite on reload/subagent import
- disabled SDK session persistence because pi already owns session history

Those fixes improved local behavior, but they also made the deeper conclusion obvious:

> The long-term problem was not a missing patch. The problem was the amount of bespoke protocol translation sitting between pi and Claude Code.

### 2026-04-10 - Architectural pivot to ACP

The project then pivoted to a new approach:

- keep **pi** as the top-level harness
- keep **Claude Code** as Claude Code
- remove as much bespoke bridge logic as possible
- connect them through the **Agent Client Protocol (ACP)**

That means this repository is no longer trying to be a custom re-implementation of Claude Code behavior inside pi.

Instead, it is now a **thin ACP client extension for pi**.

### 2026-04-10 - Reframing after reviewing agent-shell and the non-append model

A second design review corrected an important assumption: Pi-native tool execution is **not** the only valid way to preserve a multi-harness workflow.

If Claude Code already knows how to load:

- `~/.claude/CLAUDE.md`
- `~/.claude/skills`
- native MCP servers
- shell / PATH-based tools

then the correct bridge is often the *thinner* bridge, not the more intrusive one.

That means the preferred long-term model is now:

- **pi** owns harness UX and orchestration
- **Claude Code** owns capability loading and execution through its native paths
- **this repository** owns transport, visibility, and synchronization

This was the key architectural clarification.

### 2026-04-10 - From skeleton to usable baseline

The bridge then crossed an important threshold from "architectural skeleton" to "usable baseline":

- added visible rendering of Claude-side tool activity in pi
- added history/signature-based ACP session invalidation
- added process-group cleanup for Unix subprocess trees
- added a basic non-append settings surface
- fixed prompt extraction so pi hook/user metadata messages do not replace the actual user prompt
- validated the path with `bench.sh` against a direct Claude route

The benchmark result was not just "it runs." The ACP path produced correct answers across simple prompts, reasoning, tool use, multi-step file reading, Korean generation, and harness-aware prompts.

---

## Problem Statement

The original direct-SDK path tried to make pi and Claude Code share one behavioral model.
That required translation layers in both directions.

Over time, those layers created three structural problems:

1. **Semantic drift**
   - upstream SDK/tool behavior changed faster than the custom bridge could safely track

2. **State duplication**
   - pi had one view of the conversation
   - the provider had another
   - Claude Code had a third

3. **Bespoke recovery logic**
   - once the bridge started compensating for previous mismatches, each fix increased the next mismatch surface

The ACP pivot solves this by changing the layer boundary instead of adding more patches.

---

## Current Approach

### Principle

This extension should be a **thin transport and event-mapping layer**, not a second harness.

### Responsibilities by layer

#### pi
- owns the top-level harness
- owns session/UI/delegation/memory/agenda conventions
- selects the provider
- renders streaming output

#### this repository (`pi-shell-acp`)
- spawns `claude-agent-acp`
- initializes the ACP connection
- creates/reuses ACP sessions
- forwards prompts into ACP
- maps ACP session updates into pi stream events
- handles cancellation and process lifecycle
- should make Claude-side tool execution visible in the pi UI

#### `claude-agent-acp`
- provides the canonical ACP server for Claude Code
- owns Claude-specific ACP semantics

#### Claude Code
- remains the actual Claude-side engine
- may load its own capabilities through native configuration
- may execute tools through native MCP, shell, and Claude-side skill paths

---

## Capability Loading Model

The current architectural understanding is:

1. Pi does **not** have to execute every useful tool itself.
2. Claude Code can bring its own capabilities to the session.
3. A thin ACP bridge is valid **if it preserves observability and synchronization**.

### Preferred long-term operating model

```text
pi = harness / UX / orchestration
bridge = transport / visibility / session discipline
Claude Code = engine / native skills / MCP / execution
```

### Relationship to session-bridge

This repository is about the **vertical** connection between pi and Claude Code through ACP.
A separate **horizontal** coordination path may exist elsewhere in the ecosystem (for example a session-bridge living in `agent-config`) to let one harness/session steer or notify another.

Those two layers are complementary, not competing:

- this repository: `pi -> ACP bridge -> Claude Code`
- session-bridge: session-to-session / harness-to-harness coordination

### Non-append direction

The preferred direction is increasingly **non-append**:

- let Claude Code load its own context from `~/.claude`
- avoid duplicating the same instructions in every bridged prompt
- only inject prompt material from pi when truly necessary

### Important nuance

A thin bridge is **not** the same thing as a blind bridge.

Even if Claude executes tools natively, pi still needs to:

- show tool activity
- show status / usage progression
- detect history/state divergence
- clean up spawned processes correctly

---

## What Is Implemented Today

### Current implemented baseline

Implemented now:

- provider registration in pi
- model listing via pi's Anthropic model catalog
- subprocess spawn of `claude-agent-acp`
- ACP `initialize`
- ACP `newSession`
- ACP `prompt`
- ACP prompt cancellation
- ACP session reuse keyed by the pi session ID
- cross-process ACP session continuity for `pi:<sessionId>` mappings
- persisted session bootstrap order: `resume > load > new`
- prompt extraction that selects the real user prompt instead of trailing pi hook/user metadata messages
- streaming mapping for:
  - `agent_message_chunk` -> pi text events
  - `agent_thought_chunk` -> pi thinking events
- visible text-notice rendering for:
  - `tool_call`
  - `tool_call_update`
  - permission outcomes
- history-signature based session invalidation when pi and ACP state diverge
- process-group cleanup for Unix subprocess trees
- basic settings surface for:
  - `appendSystemPrompt`
  - `settingSources`
  - `strictMcpConfig`
- local smoke testing through `run.sh`
- benchmark coverage through `bench.sh`

### Current module layout

- `index.ts` - pi provider registration and top-level stream entry
- `acp-bridge.ts` - subprocess lifecycle, ACP connection, session management
- `event-mapper.ts` - ACP session updates -> pi stream events
- `run.sh` - install/auth/smoke workflow
- `bench.sh` - direct-vs-ACP benchmark runner

---

## What Is Still Missing

The following items are intentionally **not** claimed as complete:

- richer pi-side rendering of `tool_call` / `tool_call_update` beyond the current visible text notices
- history-preserving replay after session invalidation
- deeper long-running validation of process-tree cleanup across real workloads
- a complete strategy for explicit vs automatic MCP routing
- package/repository/provider renaming after stabilization
- long-horizon daily-driving validation across larger real projects

### Why these are important

These are not just polish items.
They affect correctness and operability:

- without visible tool activity, pi becomes blind while Claude works
- without replay after invalidation, history edits can correctly reset the session but still lose prior context
- without robust shutdown under real workloads, Claude-side shells can outlive the bridge

---

## Design Boundaries

This repository should **not** reintroduce:

- prompt reconstruction from full pi history as a default mechanism
- a second session ledger for "recovered" tool state
- custom tool-call semantics that fight the ACP/Claude path
- ad-hoc provider-side emulation of Claude Code internals
- large-scale argument/tool translation layers unless proven necessary

This repository **should** own:

- transport
- session lifecycle discipline
- event visibility
- error reporting
- bridge-specific safety and cleanup

---

## Development Workflow

### Install dependencies

```bash
npm install
```

### Type-check

```bash
npm run typecheck
```

### Local smoke test

```bash
./run.sh smoke .
```

The current smoke workflow checks two things:

1. pi can load the provider and list models
2. the ACP bridge can create a session, send a prompt, and receive a real response

### Benchmark

```bash
./bench.sh .
```

Useful environment overrides:

```bash
PI_BENCH_SUITE=quick ./bench.sh .
PI_BENCH_MODEL_DIRECT=github-copilot/claude-sonnet-4.6 ./bench.sh .
PI_BENCH_MODEL_SDK=claude-agent-sdk/claude-sonnet-4-6 ./bench.sh .
```

The benchmark is especially useful after changing:

- prompt extraction
- session invalidation
- settings/defaults
- tool visibility

### Local setup into another pi project

```bash
./run.sh setup ~/repos/gh/agent-config
```

This will:

- install dependencies
- sync pi auth alias data
- install this local package path into the target project's `.pi/settings.json`
- run a smoke test

---

## Environment Overrides

### Override the ACP server command

```bash
export CLAUDE_AGENT_ACP_COMMAND='node /path/to/claude-agent-acp/dist/index.js'
```

If unset, the bridge tries:

1. the locally installed `@agentclientprotocol/claude-agent-acp` package
2. `claude-agent-acp` from `PATH`

### Permission mode for ACP requests

```bash
export CLAUDE_ACP_PERMISSION_MODE=approve-all
```

Supported values today:

- `approve-all`
- `approve-reads`
- `deny-all`

### Provider settings surface

The bridge reads provider settings from:

- `~/.pi/agent/settings.json`
- `<project>/.pi/settings.json`

Project settings override global settings.

Example:

```json
{
  "claudeAgentSdkProvider": {
    "appendSystemPrompt": false,
    "settingSources": ["user"],
    "strictMcpConfig": false
  }
}
```

Current semantics:

- `appendSystemPrompt: false`
  - do not forward pi's system prompt append into Claude
  - prefer Claude-side loading from standard paths
- `settingSources`
  - controls which Claude settings layers are loaded
- `strictMcpConfig`
  - when `true`, passes `--strict-mcp-config` through Claude Code

### Cross-process session continuity cache

For pi-backed sessions only, the bridge persists a minimal session mapping at:

```text
~/.pi/agent/cache/pi-shell-acp/sessions/<sha256(sessionKey)>.json
```

Properties of this cache:

- persists only `pi:<sessionId>` mappings
- never persists `cwd:<cwd>` fallback sessions
- stores only the ACP session ID plus compatibility metadata
- ordinary process shutdown keeps the persisted mapping so the next pi process can reconnect
- incompatibility or explicit bridge close invalidates the persisted mapping and starts fresh

Default behavior when no settings are present:

- `appendSystemPrompt: false`
- `settingSources: ["user"]`
- `strictMcpConfig: false`

---

## Conclusion

This repository explored two approaches to connecting pi with Claude Code:

### Phase 1: Direct SDK Bridge (2026-04-09)
Used the Claude Agent SDK directly inside a pi provider. Collapsed under bespoke glue — tool mapping, argument rewriting, prompt reconstruction, session emulation.

### Phase 2: ACP Bridge (2026-04-10)
Pivoted to ACP (Agent Client Protocol). Achieved a working baseline — smoke tests, benchmarks, prompt routing, tool visibility all passed. The architecture was sound.

### Phase 3: Conclusion (2026-04-10)
Meanwhile, **ben's approach** (`pi-claude-code-use`) proved that a much simpler path existed:
- pi calls Claude API directly (built-in `anthropic` provider)
- A thin package patches Claude Code capabilities into pi
- No subprocess, no ACP, no session synchronization
- Already working in `agent-config` as the default Claude path

The ACP bridge was a good experiment — it validated that the protocol works and the bridge can be thin. But when a simpler solution covers the same needs, simplicity wins.

### What Was Learned

1. **Thin bridges are good, but no bridge is better.** ACP proved the concept, but eliminating the intermediate layer entirely was the real win.
2. **pi already owns tool execution.** Delegating tools back to Claude Code through ACP was architecturally clean but practically redundant.
3. **Benchmark parity isn't enough.** The ACP bridge matched direct API performance, but the operational complexity (subprocess lifecycle, session state sync, process cleanup) wasn't justified.
4. **The ben approach is the right level of abstraction.** A package that patches capabilities into pi's existing provider is the minimal viable integration.

### Legacy

This code remains as reference for:
- ACP client implementation patterns
- pi provider extension architecture
- prompt extraction from pi context
- event mapping between ACP and pi streaming
- benchmark methodology for provider comparison

---

## Design Rule (Historical)

The guiding principle that led to this conclusion:

> If a proposed change makes this repository more magical, more stateful, or more "special," it is probably moving in the wrong direction.
>
> The goal is not to be clever.
> The goal is to be thin, observable, and reliable.
>
> And sometimes the thinnest bridge is no bridge at all.
