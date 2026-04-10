# claude-agent-sdk-pi

> Transitional repository name. The package name and provider ID are kept for compatibility, but the runtime architecture has pivoted from a direct Claude Agent SDK bridge to an ACP-first bridge.

![Demo](screenshot.png)

## Status

**Current phase:** Phase 1 ACP bridge is implemented and smoke-tested.

**Current runtime path:**

```text
pi
  -> claude-agent-sdk-pi   (this extension; thin ACP client)
    -> claude-agent-acp    (canonical ACP server for Claude Code)
      -> Claude Code
```

**Compatibility note:**
- Package/repo name is still `claude-agent-sdk-pi`
- Provider ID is still `claude-agent-sdk`
- A rename may happen later, after the ACP path is stable

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

This shift is the core design decision of the project.

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
- forwards the current user prompt
- maps ACP session updates into pi stream events
- handles cancellation and process lifecycle

#### `claude-agent-acp`
- provides the canonical ACP server for Claude Code
- owns Claude-specific ACP semantics

#### Claude Code
- remains the actual Claude-side engine
- keeps its own native behavior through the ACP server path

### What this explicitly avoids

This repository should **not** reintroduce:

- prompt reconstruction from full pi history
- a second session ledger for “recovered” tool state
- custom tool-call semantics that fight the ACP/Claude path
- ad-hoc provider-side emulation of Claude Code internals

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

## What Is Not Done Yet

The following items are intentionally **not** claimed as complete:

- rich pi-side rendering of `tool_call` / `tool_call_update`
- ACP `loadSession` / resume / replay support
- a deliberate long-term strategy for pi-native tool routing
- full settings/config surface for the new ACP bridge
- package/repository/provider renaming after stabilization
- full documentation refresh across every historical note in the repo

---

## Tool Strategy (Current Reality)

At the moment, this repository is focused on making the **ACP path itself** correct and minimal.

That means the current implementation is **not** trying to recreate the previous “pi executes all Claude-requested tools through a custom direct bridge” model.

The architectural priority is:

1. make the ACP path reliable
2. keep the extension small
3. only revisit tool-routing decisions after the transport/session layer is stable

If a future phase reintroduces pi-native tool execution, it should be treated as a deliberate design project — not as a quick compatibility patch.

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

This is intentionally minimal for Phase 1.

---

## Roadmap

### Near-term

- improve pi-side rendering for tool updates
- add ACP session load/reuse beyond the current live-process model
- tighten error reporting and diagnostics
- document the new architecture more rigorously

### Mid-term

- decide whether pi-native tool routing is worth reintroducing
- add a clearer configuration surface for bridge behavior
- rename the repository/provider once the architecture settles

### Long-term

- keep the bridge boring
- minimize custom semantics
- rely on ACP as the stable boundary instead of growing another bespoke layer

---

## Design Rule

If a proposed change makes this repository more magical, more stateful, or more “special,” it is probably moving in the wrong direction.

The goal is not to be clever.
The goal is to be thin, standard, and reliable.
