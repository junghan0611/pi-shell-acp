# AGENTS.md — Maintainer Guidelines for pi-shell-acp

This document is for agents that own this repo. It contains invariant principles and reproducible verification methods — not specifications that change.

## What This Repo Is

ACP bridge provider that connects pi to ACP backends (Claude Code, Codex). Pi stays the harness; each backend keeps its own identity.

Two layers:

- **Layer A — ACP bridge**: provider registration, ACP subprocess lifecycle, session bootstrap (`resume > load > new`), prompt forwarding, event mapping, MCP injection
- **Layer B — Entwurf orchestration**: spawn/resume, target registry, identity preservation, MCP adapter (`pi-tools-bridge`), session bridge (`session-bridge`)

## Code Principle — Crash, Don't Warn

Code in this repo is used as a tool by agents. The core invariant for agent-facing tools:

> **Never warn. Throw.**

When an agent sees a warning, it interprets it as "I did something wrong" and starts flailing — rewording prompts, building workarounds, apologizing. The actual problem is the tool is broken, but the agent blames itself.

- Bad config → `throw` (e.g. `McpServerConfigError`)
- Bad path → spawn explodes (no warning)
- Bad model id → fail fast, no fallback attempt
- `catch {}` is allowed only for environment probing (optional package detection, ldd exit code variance)
- `console.warn` is allowed only in stderr diagnostic lines (read by operators, not agents)

## Hard Rules

1. **One surface name**: provider `pi-shell-acp`, model `pi-shell-acp/...`, settings `piShellAcpProvider`. No legacy aliases.
2. **Bootstrap order**: `resume > load > new`. Always.
3. **Session persistence**: only `pi:<sessionId>` is persisted. `cwd:<cwd>` is never persisted.
4. **MCP injection**: only via `piShellAcpProvider.mcpServers`. No ambient `~/.mcp.json` scanning.
5. **Config change → session invalidation**: changing backend or mcpServers automatically invalidates the persisted session. No stale reuse.
6. **Shutdown → preserve mapping**: ordinary process exit keeps persisted mapping intact.
7. **Dual-backend claim → dual-backend verification**: if the repo claims Claude + Codex support, both must pass runtime smoke.
8. **This bridge is not a second harness**: no prompt reconstruction, no transcript hydration, no tool result ledger, no Claude Code emulation.
9. **Identity preservation, not config inheritance** (both backends): pi-shell-acp borrows each backend's *identity* (system prompt preset, model behavior, tool implementations) but defines its own *operating surface*.
   - **Claude**: tools default to the pi baseline (`Read/Bash/Edit/Write`, plus `Skill` when `skillPlugins` is non-empty) so the system prompt's advertised tools and the SDK's actual tool surface match. The SDK's deferred tools (`AskUserQuestion`, `Cron*`, `Task*`, `Worktree*`, `EnterPlanMode`/`ExitPlanMode`, `Monitor`, `NotebookEdit`, `PushNotification`, `RemoteTrigger`, `WebFetch`, `WebSearch`) are explicitly added to `disallowedTools` so the system-reminder block that advertises them via ToolSearch does not slip past the `tools` filter. Skills are injected explicitly via `skillPlugins`, not via `~/.claude/skills/` discovery. MCP is the bridge servers only (`strictMcpConfig: true` by default, `settingSources: []`). Permissions are granted explicitly via `permissionAllow` wildcards. The user's `~/.claude/settings.json` `permissions.defaultMode` (which `claude-agent-acp`'s SettingsManager reads independently of `settingSources`) is shielded by spawning `claude-agent-acp` with `CLAUDE_CONFIG_DIR` pointed at a pi-owned overlay (`~/.pi/agent/claude-config-overlay/`) — pi-authored `settings.json` + symlinks for every other entry. Hooks/env/plugins are intentionally *not* inherited; opt in per-config when needed.
   - **Codex**: codex-acp exposes no `_meta` options surface, so the operating mode is pinned via codex-rs `-c key=value` flags at launch. Default is `approval_policy=never` + `sandbox_mode=danger-full-access` + `model_auto_compact_token_limit=i64::MAX` — pi-YOLO parity with the Claude side and the only sandbox preset that lets pi-baseline skills (e.g. `gogcli` reading `~/.gnupg/`) actually run. The operator's personal `~/.codex/config.toml` (`model`, `model_reasoning_effort`, `personality`, `[projects."*"].trust_level`, `[notice.*]`) is shielded by spawning codex-acp with `CODEX_HOME` pointed at a pi-owned overlay (`~/.pi/agent/codex-config-overlay/`) — pi-authored minimal `config.toml` + symlinks for every other entry. Operators can opt into a tighter mode with `PI_SHELL_ACP_CODEX_MODE=auto` or `=read-only`; the compaction guard is independent and toggled separately via `PI_SHELL_ACP_ALLOW_COMPACTION=1`.

## Verification — Reproducible Gates

All gates run through `./run.sh`:

```bash
# Full install + verification (one shot)
./run.sh setup /path/to/consumer-project

# Individual gates
pnpm typecheck                          # TypeScript type check
./run.sh check-registration             # pi registration
./run.sh check-mcp                      # MCP normalization logic (no subprocess)
./run.sh check-models                   # curated model allowlist + context caps
./run.sh check-backends                 # backend adapter detection
./run.sh smoke-all /path/to/project     # Claude + Codex runtime smoke (required)
./run.sh verify-resume /path/to/project # cross-process continuity
./run.sh check-bridge /path/to/project  # MCP bridge visibility + invocation
./run.sh sentinel /path/to/project      # 6-cell entwurf matrix
./run.sh session-messaging /path/to/project # 4-case cross-session messaging
```

If any gate fails, do not commit.

## Verification — Agent Interview (Axis 2)

Separate from protocol smoke (above), a real `pi-shell-acp/<model>` session must answer the interview. [VERIFY.md §1A](./VERIFY.md) defines Layer 0–4:

- Layer 0: self-recognition at session start (did it read the engraving?)
- Layer 1: natural use of native tools
- Layer 2: awareness of pi MCP tool boundary
- Layer 3: focus retention as turns accumulate
- Layer 4: quality compared to direct Claude Code

**Passing protocol smoke alone is not enough. The interview must also pass.** Pipes can be connected and the water can still taste wrong.

## Engraving

A short text delivered to the agent once at session bootstrap. Lives in [`prompts/engraving.md`](./prompts/engraving.md). Six lines. Do not grow it beyond that.

- Claude: `_meta.systemPrompt.append`
- Codex: first prompt turn `ContentBlock` prepend
- Template variables: `{{backend}}`, `{{mcp_servers}}` — injected dynamically

**This is not an operating contract. It is an invocation.** One instruction: "don't guess, read." One declaration: "not workers, siblings."

## Entwurf

Uses `entwurf` instead of `delegate` to avoid collisions with existing pi ecosystem delegation terms.

- Spawning creates a sibling, not a worker
- Default mode is `sync`. Async is opt-in (Phase 0.5)
- Target registry: `pi/entwurf-targets.json` (SSOT)
- Identity Preservation Rule: model override is not allowed on resume

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
| `pi-extensions/entwurf.ts` | entwurf spawn (sync + async) |
| `pi-extensions/lib/entwurf-core.ts` | shared core: registry + identity preservation |
| `pi-extensions/entwurf-control.ts` | Unix-socket control plane (ingested from Armin Ronacher) |
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

Versions follow the pins in `package.json` / `run.sh`. Mismatches are caught by `check-backends` and setup preflight.

## Working Style

- Surgical changes. One thing at a time.
- Ask: does this belong in pi? In Claude Code? Or here?
- Resist the urge to make the bridge more magical than necessary.

## References

- [VERIFY.md](./VERIFY.md) — manual verification guide + Layer 0–4 interview
- [agent-shell](https://github.com/xenodium/agent-shell) — Emacs ACP client, origin of `resume > load > new`
- [claude-agent-acp](https://github.com/agentclientprotocol/claude-agent-acp) — ACP server
- [agent-config](https://github.com/junghan0611/agent-config) — real consumer repo
