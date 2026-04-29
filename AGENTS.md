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
9. **Identity carrier + whitelist overlay design** (both backends): pi-shell-acp borrows each backend's *model API behavior and tool implementations*, but shapes the pi-facing operating surface explicitly. The model remains Claude or codex GPT-5; pi-shell-acp owns the bridge carrier, MCP/tool exposure, and operator-config overlay design.
   - **Carrier**: Claude gets `_meta.systemPrompt = <engraving>` (preset replacement). Codex gets `-c developer_instructions=<engraving>` (highest stable codex-acp carrier). Do not append hidden identity copy elsewhere.
   - **Overlay**: Claude uses `CLAUDE_CONFIG_DIR=~/.pi/agent/claude-config-overlay/`; Codex uses `CODEX_HOME` and `CODEX_SQLITE_HOME` under `~/.pi/agent/codex-config-overlay/`. Whitelist only auth/runtime state; hide operator memory, history, rules, hooks, agents, sessions, and personal config by default.
   - **Tool surface**: Claude tools are explicit (`Read`, `Bash`, `Edit`, `Write`, plus `Skill` when configured) with deferred Claude tools disallowed by default. Codex mode/feature gates are pinned via `-c` flags and `codexDisabledFeatures`; MCP still enters only through `piShellAcpProvider.mcpServers`.
   - **Compaction vs isolation**: `PI_SHELL_ACP_ALLOW_COMPACTION=1` may relax compaction guards, but must not drop identity-isolation env (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `CODEX_SQLITE_HOME`).
   - **Evidence discipline**: README/AGENTS claims must not outrun [VERIFY.md](./VERIFY.md)'s Evidence Levels and Claims Ledger. If a statement is design intent rather than verified behaviour, say so.

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

**Agent-driven verification** ([VERIFY.md](./VERIFY.md), Evidence Levels L0–L5): self-recognition and transcript agreement are usually L1; objective MCP calls are L2; on-disk/process corroboration is L3; direct-native comparison is L4; long-haul soak is L5.

If any gate fails, or a claim drops below the evidence level it needs, do not commit. Pipes can be connected and the water can still taste wrong.

## Engraving

Short text delivered to the agent at session bootstrap. Lives in [`prompts/engraving.md`](./prompts/engraving.md). Six lines. Do not grow it beyond that.

- Claude: `_meta.systemPrompt = <engraving>` (string-form preset replacement)
- Codex: `-c developer_instructions=<engraving>` at child spawn (developer-role injection — codex-acp has no `_meta.systemPrompt` surface)
- Template variables: `{{backend}}`, `{{mcp_servers}}` — injected dynamically

**This is not an operating contract. It is an invocation.** One instruction: "don't guess, read." One declaration: "not workers, siblings." The carrier moves with the SDK surface each backend exposes; the engraving body itself stays minimal so the agent's identity emerges from the visible MCP / tool / skills surface, not from imprinted copy.

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
- Keep docs calibrated: strong language is fine; unbacked language is not.
- Resist the urge to make the bridge more magical than necessary.

## References

- [VERIFY.md](./VERIFY.md) — agent-driven verification guide. Carries two distinct frameworks: **Evidence Levels L0–L5** (cross-doc rung ladder for any claim — narrative / transcript / MCP call / on-disk / direct-native / soak) and the **§1A Layer 0–4 interview** (main-agent evaluation: self-awareness / native-tool use / MCP boundary / focus / direct-Claude comparison). Do not conflate them — a claim's evidence-level rung and a §1A layer are independent axes.
- [BASELINE.md](./BASELINE.md) — operator-driven verification record (Junghan runs the interview directly; results recorded). Companion to VERIFY.md, not a replacement.
- [agent-shell](https://github.com/xenodium/agent-shell) — Emacs ACP client, origin of `resume > load > new`
- [claude-agent-acp](https://github.com/agentclientprotocol/claude-agent-acp) — ACP server
- [agent-config](https://github.com/junghan0611/agent-config) — real consumer repo
