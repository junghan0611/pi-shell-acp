# pi-shell-acp

Use Claude Code through the official Agent Client Protocol (ACP) path inside pi. Codex is supported as a second backend so the bridge's ACP boundary can be verified against a non-Anthropic ACP server.

> **Status: Public, active development.**
> This is real working code, but it is still young. Expect issues and verify it in your own workflow before relying on it all day.

![pi-shell-acp demo](docs/assets/pi-shell-acp-demo.gif)

`pi-shell-acp` connects pi to Claude Code and Codex through the same protocol path used by ACP clients like Zed and Obsidian — no OAuth proxy, no CLI transcript scraping, no Claude Code emulation. The bridge respects each backend's minimum identity boundary (the model is Claude or Codex) while owning its own operating identity carrier on top.

```text
pi
  -> pi-shell-acp
    -> claude-agent-acp | codex-acp
      -> Claude Code | Codex
```

> **Direction note.** `pi-shell-acp` is the reverse of [`pi-acp`](https://github.com/svkozak/pi-acp): `pi-acp` lets external ACP clients talk *to* pi; `pi-shell-acp` lets pi talk *to* ACP backends.

## How to Read This Project

If you see words like *entwurf* or *engraving* and wonder why a coding tool has philosophical vocabulary — this section is for you.

**The problem.** Pi users who subscribe to Claude Code have no official way to use that subscription inside pi. The workarounds that exist either violate Anthropic's Terms of Service or rely on fragile hacks that break without warning. This project exists because the maintainer tried every one of those paths and needed something that wouldn't get his shared company account banned.

**The solution.** ACP (Agent Client Protocol) is the official protocol that Zed and Obsidian use to connect to Claude Code. `pi-shell-acp` uses the same protocol — it connects pi to Claude Code as a bridge, keeping pi as the harness and Claude Code as itself.

**Why Codex too.** Codex already runs natively in pi, so the ACP path is not a workaround for Codex. It is supported here as a second backend kept to verify the bridge's ACP boundary against a non-Anthropic ACP server.

**Why "entwurf" (not "delegate").** Pi's ecosystem already has users building their own delegation logic. To avoid naming collisions, this project uses *entwurf* — German for "draft" or "projection." When you invoke entwurf, you don't spawn a worker subprocess; you summon a sibling that holds the same tool. The difference matters: workers report to a master, siblings coordinate through messages.

**Why "engraving."** When the agent starts through this bridge it sees the model's underlying API (Claude or the codex GPT-5 line) but doesn't know it's reached *through* pi. The engraving is a short text (6 lines in [`prompts/engraving.md`](./prompts/engraving.md)) that tells the agent: "you are not alone — read your MCP servers to see what's connected." Each backend gets the engraving at the highest stable identity-carrier surface it exposes — for Claude that's the system prompt itself (string-form preset replacement), for Codex it's the codex `developer_instructions` config slot — and the operator's personal config under `~/.claude/` / `~/.codex/` stays out of the bridge's view via narrow whitelist overlays. Without the engraving, the agent guesses. With it, the agent reads.

**Why this matters for daily use.** Every friction point compounds across many interactions over a working day. The verification depth in [VERIFY.md](./VERIFY.md) exists because the maintainer uses this bridge daily and keeps hitting edge cases worth recording.

## History — How We Got Here

Before this bridge, pi users who wanted Claude tried several paths. Each taught something.

| Path | What it taught |
|------|----------------|
| [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) | OAuth proxy works for chat, but tools need a deeper integration |
| [prateekmedia/claude-agent-sdk-pi](https://github.com/prateekmedia/claude-agent-sdk-pi) | Stateless turn accumulation degrades quality — sessions need to be turn-aware |
| [@benvargas/pi-claude-code-use](https://www.npmjs.com/package/@benvargas/pi-claude-code-use) | Native-level quality is achievable — proved the ceiling for what pi + Claude can feel like |
| [proxycli](https://github.com/junghan0611/proxycli) | CLI wrapping gives full tools + skills, but depends on policy that can change |
| **pi-shell-acp** | ACP is the protocol-level answer — official, turn-aware, session-persistent |

Each prior approach contributed to the understanding that led here. `pi-shell-acp` chose ACP because it is the protocol path that Zed and Obsidian use — the same level Anthropic supports for ACP clients.

## Install & Setup

### Consumer install

```bash
# 1. register with pi
pi install git:github.com/junghan0611/pi-shell-acp

# 2. wire MCP servers into your project
cd /path/to/your-project
~/.pi/agent/git/github.com/junghan0611/pi-shell-acp/run.sh install .

# 3. verify
pi --list-models pi-shell-acp
pi --model pi-shell-acp/claude-sonnet-4-6 -p 'reply with ok'
```

### Developer install

```bash
git clone https://github.com/junghan0611/pi-shell-acp ~/repos/gh/pi-shell-acp
cd ~/repos/gh/pi-shell-acp
pnpm install
pi install ./
./run.sh install /path/to/your-project
./run.sh smoke-all /path/to/your-project
```

### Codex backend

```bash
pnpm add -g @zed-industries/codex-acp@0.12.0
./run.sh smoke-codex /path/to/your-project
```

Backend is inferred from the model: Anthropic models → `claude`, OpenAI models → `codex`. Set `backend` explicitly only when you want to pin it.

### Settings

Recommended reference shape for a pi-shell-acp development session lives in [`pi/settings.reference.json`](./pi/settings.reference.json):

```json
{
  "compaction": {
    "enabled": false
  },
  "piShellAcpProvider": {
    "appendSystemPrompt": false,
    "settingSources": [],
    "strictMcpConfig": true,
    "showToolNotifications": true,
    "tools": ["Read", "Bash", "Edit", "Write"],
    "skillPlugins": [],
    "permissionAllow": ["Read(*)", "Bash(*)", "Edit(*)", "Write(*)", "mcp__*"],
    "mcpServers": {
      "pi-tools-bridge": {
        "command": "/path/to/pi-shell-acp/mcp/pi-tools-bridge/start.sh",
        "args": []
      },
      "session-bridge": {
        "command": "/path/to/pi-shell-acp/mcp/session-bridge/start.sh",
        "args": []
      }
    }
  }
}
```

`mcpServers` is the **only** way to inject MCP servers into ACP sessions — explicit allowlist, no ambient config scanning. `./run.sh install` pre-populates the bundled `pi-tools-bridge` and `session-bridge` entries with the correct local paths. Invalid entries fail fast with `McpServerConfigError`.

Backend is inferred from the selected model. Set `backend` only when you intentionally want to pin one backend.

#### Operating-surface contract — Claude backend

`pi-shell-acp` is a thin bridge: it borrows the Claude model API's *behavior and tool implementations* but **replaces Claude Code's system-prompt preset** with pi's engraving so the agent's identity context matches what pi exposes. SDK Options' `systemPrompt` accepts a string for full preset replacement (claude-agent-acp `acp-agent.ts:1685`, claude-agent-sdk `sdk.d.ts:1695`); pi-shell-acp delivers the rendered engraving via `_meta.systemPrompt = <string>`. The result is that the claude_code preset's `# auto memory` guidance, per-cwd MEMORY.md path advertisement, and other dynamic sections are gone from the system prompt — the engraving sits directly above the SDK's hard-wired minimum identity prefix (_"You are a Claude agent, built on Anthropic's Claude Agent SDK."_), which is the boundary pi-shell-acp deliberately respects. The Claude session meta is built from these explicit fields:

| Field | Default | Purpose |
|-------|---------|---------|
| `tools` | `["Read", "Bash", "Edit", "Write"]` | Built-in tools exposed to Claude. Matches the pi baseline so the system prompt's `Available tools:` line and the SDK's actual tool surface stay aligned. Override to widen (e.g. add `"Grep"`) or further narrow per session. When `skillPlugins` is non-empty the resolved settings layer auto-adds `"Skill"` to this list — required because the SDK's skill-listing emitter is gated on `tools.some(name === "Skill")` and skips the listing block otherwise. |
| `settingSources` | `[]` | SDK isolation mode — no filesystem inheritance from `~/.claude/settings.json`, project `.claude/settings.json`, or local. Hooks, env, plugins, and skills declared via Claude Code's filesystem layout are *not* picked up. Opt in by setting to `["user"]` etc. when you want the inheritance. |
| `strictMcpConfig` | `true` | Only the MCP servers in `mcpServers` reach the backend. Ambient `~/.mcp.json` and Claude Code-side MCP entries are ignored. |
| `skillPlugins` | `[]` | Absolute paths to Claude Code plugin directories. Each entry must be a directory containing `.claude-plugin/plugin.json` (manifest below) and `skills/<name>/SKILL.md` files. Each path is injected into the SDK as `{ type: "local", path }`. This is the explicit skill-injection lane — use it instead of opening `settingSources` to gain access to `~/.claude/skills/`. How operators materialize the layout (root of a repo, dedicated subdir, symlink farm under `~/.pi/`, etc.) is their call; pi-shell-acp only requires the path to satisfy the spec when it boots a session. See [agent-config](https://github.com/junghan0611/agent-config) for the reference consumer. |
| `permissionAllow` | `["Read(*)", "Bash(*)", "Edit(*)", "Write(*)", "mcp__*"]` | Wildcard rules threaded into `Options.settings.permissions.allow`. Combined with the user's `~/.claude/settings.json` `permissions.defaultMode` (which `claude-agent-acp` resolves itself and pi-shell-acp cannot override via `_meta`), this delivers de facto YOLO for the listed tools without flipping the user's native default mode. When `skillPlugins` is non-empty `Skill(*)` is auto-added so the listing surface is not silently denied. |
| `disallowedTools` | full deferred set (`AskUserQuestion`, `Cron*`, `Task*`, `Worktree*`, `EnterPlanMode`/`ExitPlanMode`, `Monitor`, `NotebookEdit`, `PushNotification`, `RemoteTrigger`, `WebFetch`, `WebSearch`) | Threaded into `Options.disallowedTools`. `Options.tools` only filters the immediate function list; the SDK separately advertises a deferred-tool set via a system-reminder block ("The following deferred tools are now available via ToolSearch") that bypasses the `tools` filter. Disallowing them keeps the agent's awareness of available tools inside pi's declared baseline. Pi's own surfaces cover every disallowed capability (`/schedule` skill for cron, `brave-search` MCP and `summarize` skill for web, entwurf for task spawning, etc.). Set to `[]` to opt out and let the deferred advertisement back in. |

Why these defaults in this shape: pi already advertises its 4-tool baseline in the system prompt it sends. Letting Claude Code surface a 15-tool preset under that prompt creates a silent declared-vs-actual mismatch. Tightening `tools` to the pi baseline makes the agent's stated and actual tools identical. The same alignment principle drives the explicit MCP / skills / permissions / deferred-tools story — pi's system prompt is the single source of truth for what the agent can do, and every layer below it is shaped to match.

Permission mode and the CLAUDE_CONFIG_DIR overlay: `claude-agent-acp` resolves the SDK's top-level `Options.permissionMode` from its own `SettingsManager` read of `~/.claude/settings.json`'s `permissions.defaultMode` (independent of `Options.settingSources`), and pi-shell-acp cannot override that resolution via `_meta`. To prevent the operator's native default mode (often `"auto"`) from leaking into pi-shell-acp sessions — and to keep the broader `~/.claude/` tree from leaking the operator's CLAUDE.md, hooks, agents, sessions data, settings.local.json, and per-project memory into the bridge — pi-shell-acp launches `claude-agent-acp` with `CLAUDE_CONFIG_DIR` pointed at a pi-owned **whitelist overlay** at `~/.pi/agent/claude-config-overlay/`. The overlay contains an author-controlled `settings.json` (`permissions.defaultMode = "default"`, `autoMemoryEnabled: false`) plus passthrough symlinks for a fixed list of entries that backend authentication and the bridge's own runtime need (`auth.json`, `cache`, `debug`, `session-bridge`, `session-env`, `shell-snapshots`, `skills`, `stats-cache.json`, `statsig`, `telemetry`); `projects/` and `sessions/` are owned by the overlay as empty directories so the binary's per-cwd MEMORY.md auto-injection finds nothing to read; binary-managed metadata (`.claude.json`, `backups/`) is preserved if real, replaced if it survived as a stale operator-side symlink from a previous overlay version. Everything else in `~/.claude/` (CLAUDE.md, hooks, agents, todos, tasks, history.jsonl, settings.local.json with personal env, plugin enablement, ...) is intentionally not present in the overlay. The overlay is rebuilt idempotently on every claude session bootstrap. An operator who explicitly exports `CLAUDE_CONFIG_DIR` in their shell keeps full control — process env wins over the bridge default.

Skill-plugin manifest shape (`<plugin-root>/.claude-plugin/plugin.json`):

```json
{
  "name": "your-skill-set",
  "description": "One-line summary of what this skill set covers, surfaced to the agent in the skill listing.",
  "author": { "name": "you" }
}
```

Each `skills/<name>/SKILL.md` under the plugin root needs YAML frontmatter with at least `name` (matching the directory name) and `description`. The body below the frontmatter loads on invocation.

The codex backend ignores the five Claude-only fields above; codex's tool surface is governed by `codex-acp` itself plus the codex-only `codexDisabledFeatures` knob documented below, and skill access on codex is currently via the `mcpServers` bridge only.

#### Operating-surface contract — Codex backend

`codex-acp` does not expose a `_meta`-style options extension to clients, so pi-shell-acp drives codex via codex-rs's `-c key=value` config flags at launch. The bridge defaults the codex session to a permissive operating mode that mirrors the pi-YOLO posture used on the Claude side. The launch-flag policy is split into two layers:

**Always-on flags** — pinned at every launch, not operator-tunable from settings.json (use the env knobs at the bottom of this section to adjust mode/compaction):

| Flag | Value | Why |
|------|-------|-----|
| `approval_policy` | `never` | Codex agent runs without prompting the operator on each command — same autonomous-operation invariant pi-shell-acp enforces on the Claude side. |
| `sandbox_mode` | `danger-full-access` | Codex's other presets (`read-only`, `workspace-write`) block reads outside the cwd, which breaks pi-baseline skills that touch workspace-external paths (e.g. `gogcli` reading `~/.gnupg/` to decrypt API tokens). Full access is the only preset that lets pi's skill set work as a coherent unit. |
| `model_auto_compact_token_limit` | `i64::MAX` | Disables codex-rs's silent auto-compaction inside the ACP session, matching the no-silent-rewrite policy the bridge enforces on both sides. |
| `web_search` | `disabled` | Native codex `web_search` tool is pinned off. pi already exposes `brave-search` MCP for web access; double-exposure would create the same declared/actual mismatch the bridge fights elsewhere. codex-rs 0.124.0's default is already `Disabled`, so this is defense-in-depth against future default flips. |
| `tools.view_image` | `false` | Best-effort disable of codex's `view_image` tool. The schema field exists in codex-rs (`config_toml.rs:514-525`) but no consumer in 0.124.0 — `tool_registry_plan.rs:381` gates `view_image` only on `has_environment` (hardcoded `true`), so this flag is forward-compat insurance. `view_image` therefore stays on; see the known-limits paragraph below. |

**Operator-tunable feature-gate policy — `codexDisabledFeatures`**: a string array of codex-rs feature keys (codex-rs/features/src/lib.rs FEATURES table) materialized at launch as `-c features.<key>=false`. Codex-only — Claude ignores it; this is the codex mirror of Claude's `disallowedTools`. Default disables six features whose default-on registration either adds tools outside pi's advertised baseline or wires the codex memory subsystem into the developer-role context:

| Feature key | Tools / behavior removed | Why disabled by default |
|-------------|--------------------------|-------------------------|
| `image_generation` | `image_gen` | Pi has no native image-generation surface; the tool is unused and creates a declared/actual mismatch against pi's 4-tool baseline. |
| `tool_suggest` | `tool_suggest` | Codex's plugin/connector elicitation surface. Pi exposes its MCP servers explicitly via `mcpServers` and has no opinion on connector discovery; the tool would only widen the surface beyond what pi advertises. |
| `tool_search` | `tool_search` (deferred-MCP search) | Equivalent of Claude's deferred-tool advertisement that pi-shell-acp also disallows on the other side. Pi already wires every MCP server it cares about into the immediate tool list; deferring some through a search surface duplicates the declared/actual mismatch the bridge is built to prevent. |
| `multi_agent` | `spawn_agent`, `send_input`, `wait_agent`, `close_agent`, `resume_agent` (collab tools v1 and v2 — v2 is gated under v1) | Pi has its own sibling-spawning surface — `entwurf` + control-socket bridge — and the codex-internal collab path would shadow it with conflicting semantics. |
| `apps` | `mcp__codex_apps__*` MCP server bundle | `with_codex_apps_mcp()` (codex-rs/codex-mcp/src/mcp/mod.rs:291) auto-injects a `codex_apps` MCP server (with GitHub etc. connectors) whenever `config.apps_enabled && CodexAuth::is_chatgpt_auth`. The `CODEX_HOME` overlay passes `auth.json` through, so the chatgpt-auth half is true; this flag closes the other half. Pi wires the MCP servers it cares about explicitly via `mcpServers`; the auto-injected bundle would duplicate / contradict that surface. |
| `memories` | codex memory loader + writer (`codex-rs/core/src/memories`) | When the feature is on, codex loads operator memory entries into the `developer` role context and writes new entries during sessions — exactly the channel pi-shell-acp must keep operator-private from. Disabling the feature is one of three layers; the others are the overlay's empty `memories/` directory (so codex-rs has nothing to read even if the gate flipped) and explicit `-c memories.generate_memories=false` / `-c memories.use_memories=false` / `-c history.persistence="none"` flags pinned at launch. |

Omit `codexDisabledFeatures` to fall through to this fail-closed default. Setting `codexDisabledFeatures: []` opts fully out of the gate policy and surfaces a one-shot stderr warning at first bootstrap (see 0.3.1 changelog). Set to a custom array to narrow or extend. codex-rs validates feature keys at config-load via `is_known_feature_key`, so a typo surfaces as a codex-acp startup warning, not a silent no-op.

A known limit on codex's tool surface: codex-rs 0.124.0 registers four tools without any config gate that the launch-flag layer or `CODEX_HOME` overlay can reach — `update_plan` and `request_user_input` are pushed unconditionally (`tool_registry_plan.rs:214`, `:236`), `view_image` is gated only on the hardcoded `has_environment = true` (`tool_config.rs:210`), and the MCP-resource trio (`list_mcp_resources`, `list_mcp_resource_templates`, `read_mcp_resource`) is gated on `params.mcp_tools.is_some()`, which is always true because pi ships MCP servers (`tool_registry_plan.rs:193`). Pi's workflows are independent of these tools, so the consequence is a declared/actual surface mismatch, not a behavioral conflict. Closing the gap requires patching codex-rs itself — out of scope for the launch-flag layer.

**Mode opt-in**: `PI_SHELL_ACP_CODEX_MODE=auto` (`workspace-write` + `on-request`) or `=read-only`. Invalid values throw at the launch surface — silent fallback to the `full-access` default would be the wrong direction. The compaction guard is independent (`PI_SHELL_ACP_ALLOW_COMPACTION=1` disables it). Both env knobs apply to the `CODEX_ACP_COMMAND` override path; the bridge's flags are appended after the operator's command, so codex-rs's "later `-c` values win" rule keeps pi-shell-acp's mode + compaction policy authoritative.

**Config overlay + identity carrier**: `codex-acp` launches with `CODEX_HOME` *and* `CODEX_SQLITE_HOME` pointed at `~/.pi/agent/codex-config-overlay/` — a pi-owned **whitelist overlay** that mirrors the Claude side's shape but is narrower because codex's leak surfaces run deeper. The overlay holds an author-controlled `config.toml` (header comment only; the `-c` flags do the real work) plus passthrough symlinks for nine entries codex needs at runtime (`auth.json`, install metadata, non-data caches, `skills`); `memories/`, `sessions/`, `log/`, `shell_snapshots/` are owned by the overlay as empty directories so codex's per-cwd memory / session / log lookups find nothing leakable; the codex thread+memory state DB (`state_5.sqlite` + WAL/SHM siblings) and telemetry DB (`logs_2.sqlite` + WAL/SHM siblings) are listed as binary-managed so codex initializes fresh copies inside the overlay rather than reading the operator's. Operator entries that the previous blacklist-style overlay would have symlinked through — `history.jsonl`, `rules/` (codex execution policy, not narrative memory), `AGENTS.md` (auto-loaded by `codex-rs/agents_md.rs` as user instructions), the operator's personal `config.toml` (`model`, `personality`, `[projects.trust_level]`, `[notice]`) — are intentionally hidden by the whitelist. Pre-migration overlays carrying stale operator-side symlinks for the binary-managed entries get those symlinks stripped on the first bootstrap with this code, so codex re-initializes fresh state. Pi's identity carrier is delivered through the same overlay-pinned config layer: the rendered engraving lands as `-c developer_instructions="<...>"` at codex-acp child spawn time, which materializes inside the codex `developer` role between the binary's `permissions` / `apps` / `skills` instruction blocks. Codex ACP exposes no `_meta.systemPrompt` surface (verified against the Rust source, `codex-acp/src/thread.rs`); `developer_instructions` is the highest stable identity carrier the codex stack offers, structurally one config layer below the Claude side's preset replacement but equivalent in authority intent. Overlay rebuilds on every spawn; an exported `CODEX_HOME` or `CODEX_SQLITE_HOME` wins over the bridge default.

Tool/permission notifications (`[tool:start]`, `[tool:done]`, `[permission:*]`) are enabled in the reference config because this repo is usually debugged by watching ACP-side tool activity. Set `showToolNotifications: false` for quieter day-to-day sessions.

`compaction.enabled: false` disables pi's auto-compaction switch and removes the TUI `(auto)` footer indicator. See **Compaction policy** below for the full gate.

Authentication is handled by Claude Code / claude-agent-acp; pi-shell-acp adds no separate auth layer.

### Smoke commands

```bash
./run.sh smoke-all .        # dual-backend gate (required)
./run.sh smoke-claude .     # Claude only
./run.sh smoke-codex .      # Codex only
./run.sh verify-resume .    # cross-process continuity with acpSessionId diagnostics
```

### Reference consumer

For a real production setup — skills, prompts, themes on top of pi-shell-acp — see [agent-config](https://github.com/junghan0611/agent-config).

## Entwurf Orchestration

`pi-shell-acp` owns the **entwurf** surface — sync/async spawn, resume, target registry, identity preservation, and the MCP/Unix-socket bridges that let pi sessions and ACP sessions reach one another.

| Path | Purpose |
|------|---------|
| `pi-extensions/entwurf.ts` | pi-native entwurf spawn (sync + async, Phase 0.5) |
| `pi-extensions/lib/entwurf-core.ts` | shared core: registry resolution + Identity Preservation Rule |
| `pi-extensions/entwurf-control.ts` | Unix-socket control plane. Ingested from [Armin Ronacher's `agent-stuff`](https://github.com/mitsuhiko/agent-stuff) (Apache 2.0). |
| `pi/entwurf-targets.json` | SSOT allowlist of `(provider, model)` spawn targets |
| `mcp/pi-tools-bridge/` | MCP adapter: `entwurf`, `entwurf_resume`, `entwurf_send`, `entwurf_peers` |
| `mcp/session-bridge/` | Claude Code ↔ pi session bridge (wire-compatible with entwurf-control) |

Full narrative and migration history: [`AGENTS.md` § Entwurf Orchestration](./AGENTS.md).

## Engraving

A short text surfaced to the ACP-side agent at session bootstrap. **Carrier-shaped, not appended** — pi-shell-acp delivers it at the highest stable identity-carrier surface each backend exposes so the agent's identity context matches what pi exposes, while the model API itself stays as the backend's own (Anthropic's Claude, OpenAI's codex GPT-5).

- Source: [`prompts/engraving.md`](./prompts/engraving.md) — six lines, `{{backend}}` and `{{mcp_servers}}` substituted at bootstrap, edit at runtime, no rebuild
- Claude carrier: `_meta.systemPrompt = <string>` → string-form preset replacement (claude_code preset's auto-memory / cwd / git-status sections drop out; engraving sits above the SDK's hard-wired minimum identity prefix)
- Codex carrier: `-c developer_instructions="<...>"` at child spawn time → lands inside the codex `developer` role between the binary's `permissions` / `apps` / `skills` blocks (codex-acp does not expose a `_meta.systemPrompt` surface)
- A/B: `PI_SHELL_ACP_ENGRAVING_PATH=/path/to/alt.md`

## Design

### What this repo owns

- provider registration (`pi-shell-acp/...`)
- ACP subprocess lifecycle + session bootstrap (`resume > load > new`)
- prompt forwarding + ACP event mapping
- entwurf orchestration (spawn, resume, messaging, registry)
- pi-facing MCP injection via `piShellAcpProvider.mcpServers`
- bridge-local cleanup and diagnostics

### What it does not do

- full-history prompt reconstruction
- backend transcript hydration into pi history
- Claude Code / Codex emulation
- broad multi-agent orchestration (entwurf is narrow, registry-gated, identity-locked)
- a second session model competing with pi

### Session persistence

Only `pi:<sessionId>` mappings are persisted at `~/.pi/agent/cache/pi-shell-acp/sessions/`. The bridge persists enough to re-attach pi to the same remote ACP session — it does not ingest backend transcript files. Pi session state is the source of truth for pi UX; backend stores (`~/.claude/`, `~/.codex/`) are interoperability side effects.

### Compaction policy

Autonomous operation requires that **no party silently rewrites the conversation behind the operator's back**. pi-shell-acp therefore takes the position that compaction is something an operator opts into, not an automatic safety net the system applies on their behalf. The gate lives in this provider so operator environments (agent-config, project-level settings, fresh clones) don't have to be configured for the policy to hold.

Concretely:

- **Host (pi)**: the provider registers a `session_before_compact` handler that returns `{ cancel: true }` for every compaction trigger pi exposes — silent overflow recovery (`isContextOverflow` Case 2 — `usage.input + usage.cacheRead > contextWindow`), threshold compaction (`shouldCompact`), explicit-error overflow recovery, and the manual `/compact` slash command. Manual invocations surface a "Compaction cancelled" message to the operator so the intent stays observable. The escape hatch is the `PI_SHELL_ACP_ALLOW_COMPACTION` environment variable: setting it to `1` / `true` / `yes` lets the handler fall through, restoring pi's default compaction behaviour for that process.
- **Backend (Claude Code)**: spawned with `DISABLE_AUTO_COMPACT=1` and `DISABLE_COMPACT=1` so the backend never compacts inside an ACP session. Operators can override these from their shell (`process.env` wins over the adapter default).
- **Backend (Codex)**: codex-rs has no env/boolean toggle for auto-compaction. It exposes the behaviour as a config threshold (`model_auto_compact_token_limit`), so the bridge raises it to `i64::MAX` via `-c model_auto_compact_token_limit=9223372036854775807` on every codex-acp launch. The `CODEX_ACP_COMMAND` override path also has these args appended (shell-quoted) so operators replacing the launch command don't accidentally re-enable backend compaction. Manual `/compact` still works at the protocol level but will be cancelled by the host-side gate above unless the operator opts out.
- **Usage forwarding**: pi-shell-acp displays the backend's `usage_update.used / size` directly as the footer context meter, matching how peer ACP clients (zed, obsidian-agent-client, openclaw-acpx) treat the same signal. Both supported backends emit per-turn occupancy: claude-agent-acp via `input + output + cache_read + cache_creation` of the last assistant result, codex-acp via `tokens_in_context_window()`. The bridge does not maintain a separate context-meter sidecar or calibration file — pi's own JSONL stays the durable transcript, and ACP `usage_update` is treated as the backend's authoritative occupancy signal. Per-component values (`input` / `output` / `cacheRead` / `cacheWrite`) are forwarded for cost and `BackendUsage` accounting; if a turn arrives without a `usage_update` (e.g. a tool-only turn that some backends skip), the footer falls back to the sum of the `PromptResponse.usage` components so it still has a value.
  - **Semantic difference vs native pi**: in pi-shell-acp sessions the footer context percentage follows the ACP backend's `usage_update.used/size`, not pi's visible-transcript estimate. This may differ from native pi because the backend counts its own prompt / cache / tool / session state on top of the visible transcript — backend system prompt, tool definitions, tool result bodies, prompt cache reads/writes, and any internal replay or compaction state all show up here. A small pi-visible conversation can map to a large ACP footer; that is the backend's own overflow-risk signal, not a meter bug. The bridge does not maintain an extra meter sidecar to "correct" this — by design the bridge surfaces what the backend says, and the operator is the one who interprets it.
  - **Diagnostic line**: every turn emits `[pi-shell-acp:usage] meter=acpUsageUpdate|componentSum source=backend|promptResponse backend=… used=… size=… raw: input=… output=… cacheRead=… cacheWrite=…`. `meter=acpUsageUpdate source=backend` means the footer matched a `usage_update` from the ACP agent; `meter=componentSum source=promptResponse` means no `usage_update` arrived this turn (some backends skip emitting on tool-only turns) and the footer fell back to summing the `PromptResponse.usage` components. This is the only state surface in the bridge; no TUI changes.

The net effect: pi never compacts unless the operator explicitly opts in (`PI_SHELL_ACP_ALLOW_COMPACTION=1`), and the backends don't compact inside an ACP session either. Long sessions are observed via the footer (the backend's `usage_update.used / size`) plus the `[pi-shell-acp:usage]` raw diagnostic; when the backend window is near its limit, the operator chooses whether to compact (after opting in), clear, or switch to a wider-context model.

### Backend capability notes

The two backends are intentionally not perfectly symmetric. Claude Code is the primary daily-use ACP target; Codex support is kept to evaluate and verify the bridge's ACP boundary against a second backend.

| Capability | Claude Code | Codex |
|---|---|---|
| ACP subprocess | `claude-agent-acp` | `codex-acp` |
| Continuity path | `resumeSession` when available | `loadSession` when available |
| Engraving delivery | `_meta.systemPrompt = <string>` (preset replacement) | `-c developer_instructions="<...>"` (developer-role injection) |
| Config overlay | `CLAUDE_CONFIG_DIR` whitelist + `autoMemoryEnabled: false` + empty `projects/`, `sessions/` | `CODEX_HOME` + `CODEX_SQLITE_HOME` whitelist + empty `memories/`, `sessions/`, `log/`, `shell_snapshots/` + binary-managed `state_5.sqlite*` / `logs_2.sqlite*` |
| Backend auto-compaction | disabled by default (`DISABLE_AUTO_COMPACT=1` + `DISABLE_COMPACT=1`) | disabled by default (`-c model_auto_compact_token_limit=i64::MAX`; appended to `CODEX_ACP_COMMAND` override path too) |
| MCP injection | `piShellAcpProvider.mcpServers` | `piShellAcpProvider.mcpServers` |

`PI_SHELL_ACP_ALLOW_COMPACTION=1` strips only the compaction-guard env vars (`DISABLE_AUTO_COMPACT`, `DISABLE_COMPACT`); identity-isolation env (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `CODEX_SQLITE_HOME`) stays regardless — those are invariants required by the operator-config-isolation design, not policy choices the compaction toggle controls.

## Repository Layout

| File | Purpose |
|------|---------|
| `index.ts` | provider registration, settings, shutdown |
| `acp-bridge.ts` | ACP lifecycle, cache, `resume > load > new` |
| `event-mapper.ts` | ACP updates → pi events |
| `engraving.ts` + `prompts/engraving.md` | bridge engraving |
| `run.sh` | install, smoke, verify, sentinel |
| `pi-extensions/` | entwurf spawn + control plane + shared core |
| `mcp/pi-tools-bridge/` | pi-side tools → ACP hosts |
| `mcp/session-bridge/` | Claude Code ↔ pi session bridge |

## References

- [xenodium/agent-shell](https://github.com/xenodium/agent-shell) — Emacs ACP client, `resume > load > new` idea origin
- [agentclientprotocol/claude-agent-acp](https://github.com/agentclientprotocol/claude-agent-acp) — canonical ACP server for Claude Code
- [agentclientprotocol](https://github.com/agentclientprotocol) — ACP protocol organization
- [junghan0611/agent-config](https://github.com/junghan0611/agent-config) — real consumer repo

## Real-world usage

The maintainer also publishes the project repositories where pi-shell-acp is exercised on actual work, so the bridge can be evaluated against day-to-day sessions instead of synthetic smoke tests. Session transcripts and design notes from these repos are progressively being made public as the harness stabilizes.

- [junghan0611/legoagent-config](https://github.com/junghan0611/legoagent-config) — daily-driver repo where Claude Code is run through pi-shell-acp via ACP. Long-running resume sessions, tool-heavy turns, and the context-meter cases that drive [issue #2](https://github.com/junghan0611/pi-shell-acp/issues/2) all originate here. Useful as a reference for what a multi-session, multi-day pi+ACP workflow looks like in practice.

## Roadmap

- **0.4.x** — entwurf surface stabilization (done in 0.4.1) and identity-check session transcripts captured in [BASELINE.md](./BASELINE.md) for public verification. Long-term: publish session-level verification data (see [pi-share-hf](https://github.com/badlogic/pi-share-hf) as a reference pipeline) so ACP-bridge behaviour can be reviewed at the session-record level, not only as a narrative.
- **0.5.0 — Compaction off → recap-as-new-question.** Replace silent compaction with explicit recap as the long-session strategy. The bridge already gates every compaction trigger; 0.5.0 codifies the alternative path the gate was always pointing at: long sessions end with a structured recap that becomes the seed for a fresh session, rather than a silently rewritten transcript.
- **0.6.0 — OpenClaw native provider.** Drop-in like ACPx — built-in provider, no extra ACP command surface, no entwurf needed (OpenClaw uses pi natively, so the bridge only has to wire the provider; the rest is pi's existing tool model).

## Status

Public, active development. The maintainer uses pi as his primary coding environment; this ACP bridge is working code, but it is still being proven through daily use.

## License

MIT
