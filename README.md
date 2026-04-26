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
    "strictMcpConfig": false,
    "showToolNotifications": true,
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

`settingSources: []` intentionally isolates the ACP-spawned Claude Code process from user/project/local Claude settings. That prevents Claude-side hooks (for example notification sounds) or ambient MCP config from silently joining a pi-owned ACP session. If you deliberately need Claude Code user settings, opt in by setting `settingSources` to `["user"]`.

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
- **Usage forwarding**: ACP usage components (input / output / cacheRead / cacheWrite) are forwarded to pi for cost/stat accounting (`BackendUsage`), but `usage.totalTokens` is deliberately rewritten so the footer percentage tracks the pi session rather than backend execution cost. ACP backends can perform multiple internal LLM calls in one pi turn (for example plan → tool → final answer), so their aggregate `totalTokens` is execution cost, not "current pi context size".
  - **Current state (`mode=visibleTranscriptOnly`)**: the footer reads a `VisibleTranscript` estimate — chars/4 over the pi session JSONL plus the current assistant output. This is honest about what it measures but understates real LLM payload because it omits backend system prompt, tool definitions, project context, and skill payloads. On a resume session with heavy `cacheRead`, the footer can read very low (e.g. `0.4%` against a `2.3M` backend cacheRead).
  - **Target (`PiOccupancy`, in progress)**: the footer will switch to `PiOccupancy = prefixOverhead + visibleTranscript + outputCorrection`, where `prefixOverhead` is calibrated once per session signature (backend + model + bridge config + system-prompt hash) and persisted as a sidecar so resume sessions get a stable reading from the first turn. Calibration samples skip tool turns to avoid the same execution-aggregate inflation. The intent is that the footer answers the same question native pi answers — *"how close is this session to the point where the operator should compact or summarize?"* — at ~90% accuracy.
  - Both modes emit a one-line diagnostic with explicit `mode=`: `[pi-shell-acp:usage] mode=visibleTranscriptOnly tokens=… backendRaw: input=… cacheRead=… …`.

The net effect: pi never compacts unless the operator explicitly opts in (`PI_SHELL_ACP_ALLOW_COMPACTION=1`), and the backends don't compact inside an ACP session either. Long sessions are observed via the footer's pi-visible context meter plus the `[pi-shell-acp:usage]` raw backend diagnostic; when the backend window is near its limit, the operator chooses whether to compact (after opting in), clear, or switch to a wider-context model.

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
