# Contributing to pi-shell-acp

This is a daily-driver bridge. Correctness beats feature breadth. Read this before opening a PR.

## What this repo is

`pi-shell-acp` is a **thin ACP bridge** that lets pi talk to Claude Code and Codex. It borrows each backend's identity (system prompt preset, model behavior, tool implementations) and shapes the *operating surface* — what tools, MCP, skills, and permissions are visible — to match pi's own policy. That is the entire scope.

If a change moves the bridge toward "second harness" — prompt reconstruction, transcript hydration, ambient discovery, silent fallback — it does not belong here.

## Hard invariants

These are enforced by code, gates, and review. Do not weaken them in a PR; if you want to argue against one, open an issue first.

1. **Bootstrap order**: `resume > load > new`. Always.
2. **Session persistence**: only `pi:<sessionId>` is persisted. `cwd:<cwd>` is never persisted.
3. **MCP injection**: only via `piShellAcpProvider.mcpServers`. No ambient `~/.mcp.json` scanning, no `~/.claude/settings.json` MCP inheritance.
4. **Operating surface, not config inheritance**: the user's filesystem Claude Code config (`~/.claude/settings.json` hooks, env, plugins, `permissions.defaultMode`) is intentionally *not* inherited. Skills come from `skillPlugins`, permissions from `permissionAllow`, deferred-tool surface from `disallowedTools`. The `CLAUDE_CONFIG_DIR` overlay enforces this even where the SDK reads filesystem independently of `settingSources`.
5. **Codex sandbox**: defaults to `full-access` (the only preset that lets pi-baseline skills like `gogcli` reach `~/.gnupg/`). Tightening is opt-in via `PI_SHELL_ACP_CODEX_MODE`. Invalid values throw, never fall back.
6. **No silent compaction**: pi-side and backend-side auto-compaction are both disabled. `PI_SHELL_ACP_ALLOW_COMPACTION=1` is the only opt-out.
7. **Dual-backend parity**: changes to operating surface, session lifecycle, or persistence must be verified against both Claude and Codex. A claim that only one backend works is a regression.
8. **This bridge is not a second harness**: no prompt reconstruction, no transcript hydration, no tool result ledger, no Claude Code emulation.

## Required gate before opening a PR

```bash
pnpm check
```

This wraps the entire static-quality surface (biome, tsc, all `check-*` gates including `check-dep-versions`). It is wired into the pre-commit hook (`.husky/pre-commit`), so a clean local commit is the first sign your change holds.

For changes that touch backend launch, session lifecycle, or `_meta` shape, also run:

```bash
./run.sh smoke-all /path/to/your-fixture-project
./run.sh verify-resume /path/to/your-fixture-project
```

These need a real ACP subprocess, so they stay manual — the hook does not run them.

## What gets PRs rejected

- adds ambient MCP discovery (project `.mcp.json`, `~/.mcp.json`, etc.) without an explicit `piShellAcpProvider.mcpServers` opt-in path
- inherits user / project / local backend config by default (i.e. flips `settingSources` away from `[]`, drops the `CLAUDE_CONFIG_DIR` overlay, removes the codex `-c` config flags)
- weakens `resume > load > new` (e.g. silently downgrading to `new` without a logged invalidation reason)
- introduces `console.warn` / silent fallback where the bridge should `throw` (see `AGENTS.md` "Never warn. Throw.")
- changes the Claude or Codex operating surface (tools, skills, MCP, permissions, sandbox) without a paired update on the other backend or an explicit "Claude-only" / "Codex-only" justification
- adds a second transcript ledger, a prompt reconstruction layer, or any state that competes with pi's session as the source of truth
- skews version pins across `package.json`, `run.sh`, and `README.md` (the `check-dep-versions` gate catches this; if it complains, fix all three)

## Style and code shape

- Read `AGENTS.md` for the full code-shape rules. Highlights:
  - fail-fast: throw on bad config, never warn-and-continue
  - no `try/catch` swallowing — `catch {}` is allowed only for environment probing
  - send-is-throw — messages aren't awaited
  - one surface name (`pi-shell-acp`)
- Comments explain *why*, not *what*. Reach for them at non-obvious decisions, especially around SDK / claude-agent-acp / codex-rs interaction edges that future maintainers won't know to look up.
- Keep changes single-responsibility per commit; bundling a refactor with a behavior change makes review and bisect painful.

## When in doubt

Open an issue describing the backend boundary you want to touch and the failure mode you observed. The repo is small; over-coordination is cheap, regression on a daily-driver tool is expensive.
