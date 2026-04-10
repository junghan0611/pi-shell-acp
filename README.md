# claude-agent-sdk-pi

> Transitional repository name. The package name and provider ID are kept for compatibility, but the runtime architecture has pivoted from a direct Claude Agent SDK bridge to an ACP-first bridge.

![Demo](screenshot.png)

## Status

**Current phase:** Phase 1 ACP bridge skeleton is implemented and smoke-tested.

**Current runtime path:**

```text
pi
  -> claude-agent-sdk-pi   (this repository; thin ACP client)
    -> claude-agent-acp    (canonical ACP server for Claude Code)
      -> Claude Code
        -> native Claude configuration
        -> native MCP configuration
        -> ~/.claude/CLAUDE.md / ~/.claude/skills
        -> CLI / PATH tools
```

**Compatibility note:**
- Package/repo name is still `claude-agent-sdk-pi`
- Provider ID is still `claude-agent-sdk`
- A rename may happen later, after the ACP path is stable

**Current caveat:**
The architecture has been reframed around Claude-side capability loading, and the bridge now exposes a basic configuration surface for append vs non-append operation, setting source selection, and strict MCP mode. However, long-session replay/reconnect and deeper validation of daily-driving behavior are still incomplete.

---

## History

### 2026-04-09 — The direct bridge started to collapse under bespoke glue

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

The result was not “Claude is weak.” The result was that the bridge itself became a parallel state machine.

That showed up as concrete failures:

- repeated or duplicated assistant output
- edit failures caused by argument-shape drift
- context contamination from recovered tool results
- unstable behavior whenever upstream SDK semantics shifted

### 2026-04-09 — Stabilization pass on the old architecture

Before changing architecture, this fork applied a short stabilization pass to confirm the immediate failure modes:

- fixed the `edit` argument mapping to pi’s `edits[]` shape
- disabled the ToolWatch ledger that re-injected stale tool results
- added a module re-registration guard to prevent provider overwrite on reload/subagent import
- disabled SDK session persistence because pi already owns session history

Those fixes improved local behavior, but they also made the deeper conclusion obvious:

> The long-term problem was not a missing patch. The problem was the amount of bespoke protocol translation sitting between pi and Claude Code.

### 2026-04-10 — Architectural pivot to ACP

The project then pivoted to a new approach:

- keep **pi** as the top-level harness
- keep **Claude Code** as Claude Code
- remove as much bespoke bridge logic as possible
- connect them through the **Agent Client Protocol (ACP)**

That means this repository is no longer trying to be a custom re-implementation of Claude Code behavior inside pi.

Instead, it is now a **thin ACP client extension for pi**.

### 2026-04-10 — Reframing after reviewing agent-shell and the non-append model

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

#### this repository (`claude-agent-sdk-pi`)
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

### Phase 1: minimal working ACP bridge

Implemented now:

- provider registration in pi
- model listing via pi’s Anthropic model catalog
- subprocess spawn of `claude-agent-acp`
- ACP `initialize`
- ACP `newSession`
- ACP `prompt`
- ACP prompt cancellation
- ACP session reuse keyed by the pi session ID
- streaming mapping for:
  - `agent_message_chunk` -> pi text events
  - `agent_thought_chunk` -> pi thinking events
- basic usage / stop-reason propagation
- local smoke testing through `run.sh`

### Current module layout

- `index.ts` — pi provider registration and top-level stream entry
- `acp-bridge.ts` — subprocess lifecycle, ACP connection, session management
- `event-mapper.ts` — ACP session updates -> pi stream events
- `run.sh` — install/auth/smoke workflow

---

## What Is Still Missing

The following items are intentionally **not** claimed as complete:

- richer pi-side rendering of `tool_call` / `tool_call_update` beyond the current visible text notices
- history-preserving replay after session invalidation
- ACP `loadSession` / resume / replay support
- deeper long-running validation of process-tree cleanup across real workloads
- a complete strategy for explicit vs automatic MCP routing
- package/repository/provider renaming after stabilization

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
- a second session ledger for “recovered” tool state
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

### Local setup into another pi project

```bash
./run.sh setup ~/repos/gh/agent-config
```

This will:

- install dependencies
- sync pi auth alias data
- install this local package path into the target project’s `.pi/settings.json`
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

Default behavior when no settings are present:

- `appendSystemPrompt: false`
- `settingSources: ["user"]`
- `strictMcpConfig: false`

---

## Roadmap

### Near-term

- validate the new settings surface under real multi-turn usage
- improve tool rendering beyond plain text notices
- add history replay or a clearer recovery story after invalidation
- validate subprocess cleanup under longer-running real tools

### Mid-term

- decide how much explicit MCP configuration the bridge should expose
- support load/resume/replay more deliberately
- rename the repository/provider once the architecture settles

### Long-term

- keep the bridge boring
- minimize custom semantics
- rely on ACP as the stable boundary
- let Claude Code load and use its own capabilities where possible

---

## Design Rule

If a proposed change makes this repository more magical, more stateful, or more “special,” it is probably moving in the wrong direction.

The goal is not to be clever.
The goal is to be thin, observable, and reliable.
