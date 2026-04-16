# AGENTS.md

> **🔄 REACTIVATED** — This repository is active again as of 2026-04-15.
> The earlier archive conclusion was superseded after the ben path was disabled pending account-risk observation.

## Status

This repository is **active again**. The ACP bridge experiment had previously been archived in favor of the ben approach, but `agent-config` has now switched back to `pi-shell-acp` as the default Claude path in pi.

The active integration now lives in:
- `~/repos/gh/pi-shell-acp` — ACP bridge provider
- `~/repos/gh/agent-config` — pi configuration loading this provider by default
- `~/repos/3rd/pi-packages` — optional ben path, currently disabled by default

## Historical Mission

This repository connected **pi** to **Claude Code** through **ACP** with the smallest possible amount of custom glue.

```text
pi
  -> this extension (thin ACP client)
    -> claude-agent-acp
      -> Claude Code
        -> native Claude config / MCP / skills / PATH
```

The guiding principle was: keep the bridge thin, observable, and reliable.
The conclusion was: the thinnest bridge is no bridge at all.

## Key Architectural Lesson

The experiment validated that:
- pi owns harness UX and orchestration
- Claude Code can own native capability loading and execution
- A thin ACP bridge can connect them with transport, visibility, and session discipline

But it also showed that when pi already handles tool execution well, the ACP intermediary layer adds complexity without proportional benefit.

## What This Repository Should Own

This repository may own:

- pi provider registration
- ACP subprocess lifecycle
- ACP initialization and session management
- prompt forwarding into ACP
- prompt selection logic that extracts the real user prompt from pi context
- ACP session-update to pi-event mapping
- visibility for Claude-side tool execution
- history/session invalidation logic when pi and ACP state diverge
- cancellation, shutdown, and diagnostics for the bridge itself
- basic provider settings for non-append operation

## What This Repository Should Not Own

Do **not** casually add back:

- prompt reconstruction from full pi conversation history as the default mechanism
- tool result ledgers that re-inject previous execution state
- large tool-name or tool-argument translation systems
- a parallel session model meant to "fix" Claude behavior
- emulation of Claude Code internals in provider code
- broad speculative abstractions for future multi-agent features

If such behavior becomes necessary, first explain **why ACP is insufficient** and **why the logic belongs here rather than upstream or in pi**.

## Layering Rules

### pi owns
- top-level harness behavior
- session UX
- memory / agenda / delegation conventions
- broader agent workflow

### this repository owns
- the narrow bridge from pi provider calls to ACP transport
- bridge-specific visibility and lifecycle control

### claude-agent-acp owns
- Claude-specific ACP server behavior

### Claude Code owns
- Claude-side native runtime behavior
- native config loading
- Claude-side MCP / skills / shell execution

When in doubt, push responsibility **down to the canonical layer** or **up to pi**, not sideways into this repo.

## Non-Append Preference

When a capability is already available through Claude Code's standard paths (for example `~/.claude`, native MCP config, or shell/PATH tools), prefer using that path over duplicating the same information in the bridge.

This does **not** mean "do nothing."
It means:

- do not duplicate configuration blindly
- do not rebuild execution paths unnecessarily
- do make execution visible to the pi user
- do keep session state honest when history changes

## Reference Commands (Historical)

```bash
npm install
npm run typecheck
./run.sh smoke .
./bench.sh .
PI_BENCH_SUITE=quick ./bench.sh .
```
