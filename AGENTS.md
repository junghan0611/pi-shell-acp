# AGENTS.md

## Mission

This repository exists to connect **pi** to **Claude Code** through **ACP** with the smallest possible amount of custom glue.

It is **not** a project to recreate Claude Code inside pi.
It is **not** a place to build a second harness.
It is **not** a place to accumulate protocol-shim logic because “one more compatibility fix” looks convenient.

The intended architecture is:

```text
pi
  -> this extension (thin ACP client)
    -> claude-agent-acp
      -> Claude Code
```

## Primary Goal

Keep the bridge thin and reliable.

If a change improves correctness by removing custom logic, that is usually aligned with the project.
If a change adds a new translation layer, shadow state machine, or semantic rewrite, it is usually suspect.

## Current Reality

- The repository name is still `claude-agent-sdk-pi`
- The provider ID is still `claude-agent-sdk`
- Those names remain for compatibility
- The runtime architecture is now ACP-first

Before making changes, read `README.md` first. The README history explains **why** this project pivoted.

## What This Repository Should Own

This repository may own:

- pi provider registration
- ACP subprocess lifecycle
- ACP initialization and session management
- minimal prompt forwarding
- ACP session-update to pi-event mapping
- cancellation, shutdown, and diagnostics for the bridge itself

## What This Repository Should Not Own

Do **not** casually add back:

- prompt reconstruction from full pi conversation history
- tool result ledgers that re-inject previous execution state
- large tool-name or tool-argument translation systems
- a parallel session model meant to “fix” Claude behavior
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

### claude-agent-acp owns
- Claude-specific ACP server behavior

### Claude Code owns
- Claude-side native runtime behavior

When in doubt, push responsibility **down to the canonical layer** or **up to pi**, not sideways into this repo.

## Change Strategy

Prefer changes that are:

- small
- explicit
- testable
- easy to delete
- easy to reason about from one file at a time

Avoid changes that are:

- magical
- compensatory
- stateful in multiple layers
- hard to validate without reading the entire codebase

## Documentation Rules

- All repository documentation should be written in **English**.
- Keep the README architecture and status sections current.
- If the bridge contract changes, update `README.md` in the same change.
- If the development workflow changes, update `run.sh` documentation and examples.

## Validation Commands

Use these before finishing significant changes:

```bash
npm install
npm run typecheck
./run.sh smoke .
```

If the change affects process spawning, prompt flow, or session reuse, run the smoke test again after the final edit.

## Local Files and Hygiene

Do not commit local harness state such as:

- `.pi/settings.json`
- ad-hoc local auth files
- machine-specific temporary debugging artifacts

Keep the repository portable.

## Review Standard

The correct review question for this repository is not:

> “Can we make it do more?”

The correct review question is:

> “Did this change make the bridge thinner, clearer, and closer to the standard ACP boundary?”
