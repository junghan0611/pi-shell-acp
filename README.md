# pi-shell-acp

Use Claude Code and Codex subscriptions inside pi through the official Agent Client Protocol (ACP) path.

> **Status: Public, active development.**
> This is real working code, but it is still young. Expect issues and verify it in your own workflow before relying on it all day.

![pi-shell-acp demo](docs/assets/pi-shell-acp-demo.gif)

`pi-shell-acp` connects pi to Claude Code and Codex through the same protocol path used by ACP clients like Zed and Obsidian — no OAuth proxy, no CLI transcript scraping, no backend identity replacement.

```text
pi
  -> pi-shell-acp
    -> claude-agent-acp | codex-acp
      -> Claude Code | Codex
```

> **Direction note.** `pi-shell-acp` is the reverse of [`pi-acp`](https://github.com/svkozak/pi-acp): `pi-acp` lets external ACP clients talk *to* pi; `pi-shell-acp` lets pi talk *to* ACP backends.

## How to Read This Project

If you see words like *entwurf* or *engraving* and wonder why a coding tool has philosophical vocabulary — this section is for you.

**The problem.** Pi users who subscribe to Claude Code or Codex have no official way to use that subscription inside pi. The workarounds that exist either violate Anthropic's Terms of Service or rely on fragile hacks that break without warning. This project exists because the maintainer tried every one of those paths and needed something that wouldn't get his shared company account banned.

**The solution.** ACP (Agent Client Protocol) is the official protocol that Zed and Obsidian use to connect to Claude Code. `pi-shell-acp` uses the same protocol — it connects pi to Claude Code and Codex as a bridge, keeping pi as the harness and each backend as itself.

**Why "entwurf" (not "delegate").** Pi's ecosystem already has users building their own delegation logic. To avoid naming collisions, this project uses *entwurf* — German for "draft" or "projection." When you invoke entwurf, you don't spawn a worker subprocess; you summon a sibling that holds the same tool. The difference matters: workers report to a master, siblings coordinate through messages.

**Why "engraving."** When Claude Code starts through this bridge, it inherits its full native identity (system prompt, tools, skills). But it doesn't know it's reached *through* pi. The engraving is a short text (6 lines in [`prompts/engraving.md`](./prompts/engraving.md)) that tells the agent: "you are not alone — read your MCP servers to see what's connected." Without it, the agent guesses. With it, the agent reads. That's the difference between confusion and self-recognition.

**Why this matters for daily use.** This is not a tool you use for an hour. It's a tool you use all day. Every friction point compounds across hundreds of interactions. The verification depth in [VERIFY.md](./VERIFY.md) exists because the maintainer uses this bridge as his primary coding environment, not as a side project.

## History — How We Got Here

Before this bridge, pi users who wanted Claude tried several paths. Each taught something.

| Path | What it taught |
|------|----------------|
| [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) | OAuth proxy works for chat, but tools need a deeper integration |
| [prateekmedia/claude-agent-sdk-pi](https://github.com/prateekmedia/claude-agent-sdk-pi) | Stateless turn accumulation degrades quality — sessions need to be turn-aware |
| [@benvargas/pi-claude-code-use](https://www.npmjs.com/package/@benvargas/pi-claude-code-use) | Native-level quality is achievable — proved the ceiling for what pi + Claude can feel like |
| [proxycli](https://github.com/junghan0611/proxycli) | CLI wrapping gives full tools + skills, but depends on policy that can change |
| **pi-shell-acp** | ACP is the protocol-level answer — official, turn-aware, session-persistent |

Each prior approach contributed to the understanding that led here. `pi-shell-acp` chose ACP because it is the same protocol path that Zed and Obsidian use — a foundation that doesn't depend on workarounds or policy exceptions.

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
pnpm add -g @zed-industries/codex-acp@0.11.1
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

`pi-shell-acp` is a thin bridge: it borrows Claude Code's *identity* (system prompt preset, model behavior, tool implementations) but keeps the *operating surface* — what tools, MCP, skills, and permissions are visible — under pi's control. The Claude session meta passed to `claude-agent-acp` is built from these explicit fields:

| Field | Default | Purpose |
|-------|---------|---------|
| `tools` | `["Read", "Bash", "Edit", "Write"]` | Built-in tools exposed to Claude. Matches the pi baseline so the system prompt's `Available tools:` line and the SDK's actual tool surface stay aligned. Override to widen (e.g. add `"Grep"`) or further narrow per session. |
| `settingSources` | `[]` | SDK isolation mode — no filesystem inheritance from `~/.claude/settings.json`, project `.claude/settings.json`, or local. Hooks, env, plugins, and skills declared via Claude Code's filesystem layout are *not* picked up. Opt in by setting to `["user"]` etc. when you want the inheritance. |
| `strictMcpConfig` | `true` | Only the MCP servers in `mcpServers` reach the backend. Ambient `~/.mcp.json` and Claude Code-side MCP entries are ignored. |
| `skillPlugins` | `[]` | Absolute paths to Claude Code plugin directories. Each entry must be a directory containing `.claude-plugin/plugin.json` (manifest below) and `skills/<name>/SKILL.md` files. Each path is injected into the SDK as `{ type: "local", path }`. This is the explicit skill-injection lane — use it instead of opening `settingSources` to gain access to `~/.claude/skills/`. How operators materialize the layout (root of a repo, dedicated subdir, symlink farm under `~/.pi/`, etc.) is their call; pi-shell-acp only requires the path to satisfy the spec when it boots a session. See [agent-config](https://github.com/junghan0611/agent-config) for the reference consumer. |
| `permissionAllow` | `["Read(*)", "Bash(*)", "Edit(*)", "Write(*)", "mcp__*"]` | Wildcard rules threaded into `Options.settings.permissions.allow`. Combined with the user's `~/.claude/settings.json` `permissions.defaultMode` (which `claude-agent-acp` resolves itself and pi-shell-acp cannot override via `_meta`), this delivers de facto YOLO for the listed tools without flipping the user's native default mode. |

Why these defaults in this shape: pi already advertises its 4-tool baseline in the system prompt it sends. Letting Claude Code surface a 15-tool preset under that prompt creates a silent declared-vs-actual mismatch. Tightening `tools` to the pi baseline makes the agent's stated and actual tools identical. The same alignment principle drives the explicit MCP / skills / permissions story.

Skill-plugin manifest shape (`<plugin-root>/.claude-plugin/plugin.json`):

```json
{
  "name": "your-skill-set",
  "description": "One-line summary of what this skill set covers, surfaced to the agent in the skill listing.",
  "author": { "name": "you" }
}
```

Each `skills/<name>/SKILL.md` under the plugin root needs YAML frontmatter with at least `name` (matching the directory name) and `description`. The body below the frontmatter loads on invocation.

The codex backend ignores all five Claude-only fields above; codex's tool surface is governed by `codex-acp` itself, and skill access on codex is currently via the `mcpServers` bridge only.

Tool/permission notifications (`[tool:start]`, `[tool:done]`, `[permission:*]`) are enabled in the reference config because this repo is usually debugged by watching ACP-side tool activity. Set `showToolNotifications: false` for quieter day-to-day sessions.

`compaction.enabled: false` disables pi's auto-compaction switch and removes the TUI `(auto)` footer indicator. The provider still independently blocks all pi-side compaction paths unless `PI_SHELL_ACP_ALLOW_COMPACTION=1` is set.

Authentication is handled by Claude Code / claude-agent-acp; pi-shell-acp adds no separate auth layer.

> **No party silently rewrites the conversation.**
>
> Compaction is gated centrally by this provider — operators do **not** need to add `compaction.enabled=false` to their pi settings. The provider registers a `session_before_compact` handler that returns `{ cancel: true }` for every compaction path pi exposes (silent overflow recovery, threshold compaction, explicit-error overflow recovery, manual `/compact`). Backend-side auto-compaction is also disabled at launch (`DISABLE_AUTO_COMPACT=1` + `DISABLE_COMPACT=1` for Claude Code; `-c model_auto_compact_token_limit=i64::MAX` for codex-acp). An operator who really wants pi-side compaction back — for example for a long-running maintenance session — can opt out via `PI_SHELL_ACP_ALLOW_COMPACTION=1` at the process level. See the **Compaction policy** section below for the full rationale.

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

A short text surfaced to the ACP-side agent once at session bootstrap. **Additive bridge context, not identity replacement** — Claude Code remains Claude Code, Codex remains Codex.

- Source: [`prompts/engraving.md`](./prompts/engraving.md) (edit at runtime, no rebuild)
- Claude: `_meta.systemPrompt.append`
- Codex: first-prompt `ContentBlock` prepend
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
| Engraving delivery | `_meta.systemPrompt.append` | first prompt `ContentBlock` prepend |
| Backend auto-compaction | disabled by default (`DISABLE_AUTO_COMPACT=1` + `DISABLE_COMPACT=1`) | disabled by default (`-c model_auto_compact_token_limit=i64::MAX`; appended to `CODEX_ACP_COMMAND` override path too) |
| MCP injection | `piShellAcpProvider.mcpServers` | `piShellAcpProvider.mcpServers` |

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

- [junghan0611/legoagent-config](https://github.com/junghan0611/legoagent-config) — primary daily-driver repo where Claude Code is run through pi-shell-acp via ACP. Long-running resume sessions, tool-heavy turns, and the context-meter cases that drive [issue #2](https://github.com/junghan0611/pi-shell-acp/issues/2) all originate here. Useful as a reference for what a "real" multi-session, multi-day pi+ACP workflow looks like in practice.

## Status

Public, active development. The maintainer uses pi as his primary coding environment; this ACP bridge is working code, but it is still being proven through daily use.

## License

MIT
