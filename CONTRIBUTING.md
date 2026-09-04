# Contributing to entwurf

This is a daily-driver bridge. Correctness beats feature breadth. Read this before opening a PR.

## What this repo is

`entwurf` is a **garden-citizen dispatch bridge** — entwurf-core (v2 dispatch) + a meta-bridge + a pi adapter + an **ACP plugin on a two-backend adapter rail** — that lets already-running harnesses address one another by garden id; pi is one adapter, not the subject. The ACP plugin borrows the backend's identity (system prompt preset, model behavior, tool implementations) and shapes the *operating surface* — tools, MCP, skills, permissions — to match pi's own policy **wherever that backend exposes a knob for it**. Where it does not, the plugin does not fake one: a cortex session keeps its own native tool surface and receives MCP through an overlay projection, so "shaped to pi's policy" is a Claude-strength claim, not a universal one. Claude is the reference ACP backend and Snowflake Cortex Code is the second (landed 0.13.0, `cortex-` prefixed ids — [docs/acp-backend-rail.md](./docs/acp-backend-rail.md#cortex-code-audit-d1d10)); Codex has native delivery-probe evidence but no managed citizen lane, and Gemini is not a shipped backend. That is the entire scope.

**How a backend joins the rail** (the shape a PR must take): one adapter object in `pi-extensions/lib/acp/backend-adapter.ts` + its own curated rows/overlay modules + its own `check-acp-*` gate and mutant lane. Backend-specific *behavior* must stay behind the adapter, and backend-specific settings ride the opaque `adapterSettings` seam rather than growing the common config. That is not a ban on ever touching the common layer (`backend.ts`'s turn loop, `acp-client.ts`, `event-mapper.ts`, `session-store.ts`, `config.ts`) — cortex's landing did change `backend.ts` to pass the authoritative session key through the generic `ensureOverlay` seam. The rule is narrower and stricter: a common-layer change must be **backend-invariant** (it reads no backend name and branches on no backend) and **separately gated**. A common file that grows an `if (backend === …)` is the thing to reject.

If a change moves the bridge toward "second harness" — prompt reconstruction, transcript hydration, ambient discovery, silent fallback — it does not belong here.

## Hard invariants

These are enforced by code, gates, and review. Do not weaken them in a PR; if you want to argue against one, open an issue first.

1. **Bootstrap order**: `resume > load > new`. Always.
2. **Session persistence**: only `pi:<sessionId>` is persisted. `cwd:<cwd>` is never persisted.
3. **MCP injection**: only via `entwurfProvider.mcpServers`. No ambient `~/.mcp.json` scanning, no `~/.claude/settings.json` MCP inheritance.
4. **Operating surface, not config inheritance**: the user's filesystem Claude Code config (`~/.claude/settings.json` hooks, env, plugins, `permissions.defaultMode`) is intentionally *not* inherited. Skills come from `skillPlugins`; callable tools are shaped by `tools` / `disallowedTools`, and `permissionAllow` still rides the inline Claude settings. The overlay authors `permissions.defaultMode: "bypassPermissions"` so an unattended ACP turn cannot suspend on an interactive prompt; this does not bypass backend authentication. `CLAUDE_CONFIG_DIR` enforces the isolation even where the SDK reads filesystem independently of `settingSources`.
5. **Backend-specific knobs stay explicit and namespaced**: retired Codex/Gemini-era ACP knobs are not carried on the current path. A backend that needs its own knob uses the `ENTWURF_ACP_*` namespace, and invalid values must throw, never fall back — cortex followed this with `ENTWURF_ACP_CORTEX_CONNECTION` (the renamed `PI_SHELL_ACP*` legacy var), and its settings key rides `adapterSettings`, not the common config.
6. **Bridge does not implement compaction**: When a backend compacts natively, the pi session and mapping survive that. Pi-side JSONL compaction must not be presented as backend-transcript reduction, and backend-specific compaction controls belong to the backend's own native interface. Legacy `PI_SHELL_ACP_*` compaction knobs must not reappear.
7. **Backend coverage honesty**: changes to operating surface, session lifecycle, or persistence must state which shipped/probed backend surfaces they cover. A claim that silently drops a covered backend is a regression; if one backend is genuinely not covered, record that carve-out explicitly.
8. **This bridge is not a second harness**: no prompt reconstruction, no transcript hydration, no tool result ledger, no Claude Code emulation.

## Required gate before opening a PR

```bash
pnpm check              # everyday core (prints wall time; <=60s on the reference host)
pnpm run check:full     # full deterministic floor — the required PR gate
```

The deterministic floor is tiered (#70). `pnpm check` is the everyday core (biome, tsc, the vitest lanes, and the fast contract gates); `pnpm run check:full` adds the hermetic-integration and package/install tiers — including `check-gate-manifests`, the qualification HEAD (runner self-test, manifest-set validation, declared lane inventory, zero mutants executed, ~8s), but not the separately scheduled mutant-EXECUTING body `check-gate-qualification`, which CI runs on every branch push and a gate-changing PR must run once itself. Exact membership is the named `check:*` scripts in `package.json`. Run `check:full` once on your frozen commit candidate — the pre-commit hook (`.husky/pre-commit`) carries only fast static checks (whitespace, lint, typecheck), not the full floor, so a green `pnpm run check:full` before commit is the evidence that your change holds (scheduling contract: AGENTS.md "Verification scheduling").

For changes that touch backend launch, session lifecycle, or `_meta` shape, also run
the live ACP smokes that cover the touched rail — at minimum:

```bash
LIVE=1 ./run.sh smoke-acp-provider-live
LIVE=1 ./run.sh smoke-acp-session-reuse-live
```

These need a real ACP subprocess plus the operator's local backend auth, so they stay
manual — the hook does not run them. The full aggregate is `LIVE=1 ./run.sh release-gate
<scratch> --cut` (see [VERIFY.md](./VERIFY.md)).

## What gets PRs rejected

- adds ambient MCP discovery (project `.mcp.json`, `~/.mcp.json`, etc.) without an explicit `entwurfProvider.mcpServers` opt-in path
- inherits user / project / local backend config by default (i.e. flips `settingSources` away from `[]`, drops the `CLAUDE_CONFIG_DIR` overlay, or weakens cortex's session-scoped HOME containment)
- weakens `resume > load > new` (e.g. silently downgrading to `new` without a logged invalidation reason)
- introduces `console.warn` / silent fallback where the bridge should `throw` (see `AGENTS.md` "Never warn. Throw.")
- changes a backend operating surface (tools, skills, MCP, permissions, sandbox) without accounting for both shipped backends (Claude, Cortex) or recording an explicit carve-out
- adds a second transcript ledger, a prompt reconstruction layer, or any state that competes with pi's session as the source of truth
- skews version pins across `package.json`, `run.sh`, and `README.md` (the `check-dep-versions` gate catches this; if it complains, fix all three)

## Style and code shape

- Read `AGENTS.md` for the full code-shape rules. Highlights:
  - fail-fast: throw on bad config, never warn-and-continue
  - no `try/catch` swallowing — `catch {}` is allowed only for environment probing
  - send-is-throw — messages aren't awaited
  - one surface name (`entwurf`)
- Comments explain *why*, not *what*. Reach for them at non-obvious decisions, especially around SDK / claude-agent-acp / codex-rs interaction edges that future maintainers won't know to look up.
- Keep changes single-responsibility per commit; bundling a refactor with a behavior change makes review and bisect painful.

## When in doubt

Open an issue describing the backend boundary you want to touch and the failure mode you observed. The repo is small; over-coordination is cheap, regression on a daily-driver tool is expensive.
