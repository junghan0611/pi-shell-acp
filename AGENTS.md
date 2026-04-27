# AGENTS.md — Maintainer Guidelines for pi-shell-acp

For agents that own this repo. Invariant principles + reproducible verification, not specs that change.

## What This Repo Is

ACP bridge provider that connects pi to ACP backends (Claude Code, Codex). Pi stays the harness; each backend keeps its own identity. Two layers:

- **Layer A — ACP bridge**: provider registration, ACP subprocess lifecycle, session bootstrap (`resume > load > new`), prompt forwarding, event mapping, MCP injection
- **Layer B — Entwurf orchestration**: spawn/resume, target registry, identity preservation, MCP adapter (`pi-tools-bridge`), session bridge (`session-bridge`)

## Code Principle — Crash, Don't Warn

Code in this repo is used as a tool by agents. Core invariant:

> **Never warn. Throw.**

When an agent sees a warning, it interprets it as "I did something wrong" and starts flailing — rewording prompts, building workarounds, apologizing. The actual problem is the tool is broken, but the agent blames itself.

- Bad config → throw (e.g. `McpServerConfigError`); same for bad path / bad model id. No fallback.
- `catch {}` only for environment probing (optional package detection, ldd exit code variance).
- `console.warn` only in stderr diagnostic lines (read by operators, not agents).

## Hard Rules

1. **One surface name**: provider `pi-shell-acp`, model `pi-shell-acp/...`, settings `piShellAcpProvider`. No legacy aliases.
2. **Bootstrap order**: `resume > load > new`. Always.
3. **Session persistence**: only `pi:<sessionId>` is persisted. `cwd:<cwd>` is never persisted.
4. **MCP injection**: only via `piShellAcpProvider.mcpServers`. No ambient `~/.mcp.json` scanning.
5. **Config change → session invalidation**: backend or `mcpServers` change automatically invalidates the persisted session. No stale reuse.
6. **Shutdown → preserve mapping**: ordinary process exit keeps persisted mapping intact.
7. **Dual-backend claim → dual-backend verification**: if the repo claims Claude + Codex support, both must pass runtime smoke.
8. **This bridge is not a second harness**: no prompt reconstruction, no transcript hydration, no tool result ledger, no Claude Code emulation.
9. **Identity preservation, not config inheritance** (both backends): pi-shell-acp borrows each backend's *identity* (system prompt preset, model behavior, tool implementations) but defines its own *operating surface*. Each backend launches with a pi-owned config overlay — `CLAUDE_CONFIG_DIR=~/.pi/agent/claude-config-overlay/`, `CODEX_HOME=~/.pi/agent/codex-config-overlay/` — that holds pi-authored config + symlinks for every other entry, so operator personal config does not leak in. Hooks/env/plugins are intentionally not inherited.
   - **Claude tool surface**: `tools` = `[Read, Bash, Edit, Write]` (+ `Skill` when `skillPlugins` non-empty). `disallowedTools` blocks the SDK's deferred-tool advertisement (`AskUserQuestion`, `Cron*`, `Task*`, `Worktree*`, `EnterPlanMode`/`ExitPlanMode`, `Monitor`, `NotebookEdit`, `PushNotification`, `RemoteTrigger`, `WebFetch`, `WebSearch`). MCP via `mcpServers` only (`strictMcpConfig: true`, `settingSources: []`). Skills via `skillPlugins` paths only. Permissions via `permissionAllow` wildcards.
   - **Codex tool surface**: `approval_policy=never` + `sandbox_mode=danger-full-access` + `model_auto_compact_token_limit=i64::MAX` pinned via `-c` flags. `web_search="disabled"` + `tools.view_image=false` pinned. `codexDisabledFeatures` (mirror of Claude's `disallowedTools`) defaults to `image_generation`/`tool_suggest`/`tool_search`/`multi_agent`/`apps`.
   - **Env knobs**: `PI_SHELL_ACP_CODEX_MODE=auto|read-only` for Codex mode opt-in; `PI_SHELL_ACP_ALLOW_COMPACTION=1` for compaction guard opt-out (both backends).

## Verification

Two axes, both required.

**Protocol smoke** (`./run.sh`):

```bash
./run.sh setup /path/to/consumer-project    # one-shot install + all gates
pnpm typecheck && ./run.sh check-backends && ./run.sh check-models && ./run.sh check-mcp && ./run.sh check-dep-versions && ./run.sh check-registration
./run.sh smoke-all /path/to/project         # Claude + Codex runtime
./run.sh verify-resume /path/to/project     # cross-process continuity
./run.sh check-bridge /path/to/project      # MCP bridge visibility + invocation
./run.sh sentinel /path/to/project          # 6-cell entwurf matrix
./run.sh session-messaging /path/to/project # 4-case cross-session messaging
```

**Agent interview** ([VERIFY.md](./VERIFY.md), Layer 0–4): self-recognition / native tool use / pi MCP awareness / focus retention / quality vs direct Claude Code.

If any gate fails or the interview drops a layer, do not commit. Pipes can be connected and the water can still taste wrong.

## Engraving

Short additive text delivered to the agent at session bootstrap. Lives in [`prompts/engraving.md`](./prompts/engraving.md). Six lines. Do not grow it beyond that.

- Claude: `_meta.systemPrompt.append`
- Codex: first prompt turn `ContentBlock` prepend
- Template variables: `{{backend}}`, `{{mcp_servers}}` — injected dynamically

**This is not an operating contract. It is an invocation.** One instruction: "don't guess, read." One declaration: "not workers, siblings."

## Entwurf

Uses `entwurf` instead of `delegate` to avoid collisions with existing pi ecosystem delegation terms.

- Spawning creates a sibling, not a worker
- Default mode is `sync`; async is opt-in (Phase 0.5)
- Target registry: `pi/entwurf-targets.json` (SSOT — bare model IDs auto-resolve here, native preferred; ACP route requires explicit `provider="pi-shell-acp"`)
- Identity Preservation Rule: model override is not allowed on resume

> **Naming pair.** *Entwurf* (기투, projection-of-self) lives here in pi-shell-acp — the mechanism by which a resident agent throws siblings forward (spawn / resume / messaging). The resident-side counterpart is *Mitsein* (공존, being-with), documented in [`agent-config/home/MITSEIN.md`](https://github.com/junghan0611/agent-config/blob/main/home/MITSEIN.md). pi-shell-acp owns the entwurf surface; resident-side conventions live in agent-config.

### Send-is-throw

Messages are thrown, not awaited.

- `entwurf_send`: fire-and-forget. No `wait_until` on the MCP bridge.
- If you need a reply, say so in the message itself.
- If you need to own the outcome, use `entwurf(mode=async)` + `entwurf_resume`.

## File Structure

| File | Purpose |
|------|---------|
| `index.ts` | provider registration, settings, shutdown |
| `acp-bridge.ts` | ACP lifecycle, cache, `resume > load > new` |
| `event-mapper.ts` | ACP events → pi events |
| `engraving.ts` + `prompts/engraving.md` | bridge engraving |
| `run.sh` | install, smoke, verify, sentinel |
| `pi-extensions/` | entwurf spawn + control plane + shared core |
| `pi/entwurf-targets.json` | spawn target allowlist |
| `mcp/pi-tools-bridge/` | `entwurf`, `entwurf_resume`, `entwurf_send`, `entwurf_peers` |
| `mcp/session-bridge/` | Claude Code ↔ pi session bridge |

## Typecheck Boundary

- `pi-extensions/entwurf.ts` + `lib/*` — included in root typecheck
- `pi-extensions/entwurf-control.ts` — excluded (ingested, type drift, runtime-verified)
- `mcp/*` — excluded (runtime strip-types, covered by behavioral tests)

## Runtime Dependencies

- `@agentclientprotocol/claude-agent-acp` — resolved from this package dependency first; `claude-agent-acp` on PATH is fallback.
- `codex-acp` — resolved from PATH. Install globally when using Codex.
- `claude` CLI — Claude Code authentication, managed separately.

Versions follow the pins in `package.json` / `run.sh`. Mismatches are caught by `check-dep-versions`.

## Working Style

- Surgical changes. One thing at a time.
- Ask: does this belong in pi? In Claude Code? Or here?
- Resist the urge to make the bridge more magical than necessary.

## References

- [VERIFY.md](./VERIFY.md) — manual verification guide + Layer 0–4 interview
- [agent-shell](https://github.com/xenodium/agent-shell) — Emacs ACP client, origin of `resume > load > new`
- [claude-agent-acp](https://github.com/agentclientprotocol/claude-agent-acp) — ACP server
- [agent-config](https://github.com/junghan0611/agent-config) — real consumer repo
