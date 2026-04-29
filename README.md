# pi-shell-acp

Use Claude Code through the official Agent Client Protocol (ACP) path inside pi. Codex is supported as a second backend so the bridge's ACP boundary can be verified against a non-Anthropic ACP server.

> **Status: Public, active development.**
> This is real working code, but it is still young. Expect issues and verify it in your own workflow before relying on it all day.
>
> **Evidence calibration.** Claims about identity, tool visibility, and native-quality behaviour are tracked in [VERIFY.md](./VERIFY.md). Current public evidence is strongest at L1–L2 for identity/tool wiring; 8-hour/day native-quality claims remain unmeasured until L4/L5 runs.

![pi-shell-acp demo](docs/assets/pi-shell-acp-demo.gif)

`pi-shell-acp` connects pi to Claude Code and Codex through the same ACP path used by Zed's Claude Code integration — no OAuth proxy, no CLI transcript scraping, no Claude Code emulation. The bridge respects each backend's minimum identity boundary (the model is Claude or Codex) while shaping the pi-facing operating surface on top.

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

**The solution.** ACP (Agent Client Protocol) is the protocol Zed uses to connect to Claude Code. `pi-shell-acp` uses the same path — pi stays the harness, Claude Code stays itself.

**Why Codex too.** Codex already runs natively in pi, so the ACP path is not a workaround for Codex. It is supported here as a second backend kept to verify the bridge's ACP boundary against a non-Anthropic ACP server.

**Why "entwurf" (not "delegate").** Pi's ecosystem already has users building their own delegation logic. To avoid naming collisions, this project uses *entwurf* — German for "draft" or "projection." When you invoke entwurf, you don't spawn a worker subprocess; you summon a sibling that holds the same tool. The difference matters: workers report to a master, siblings coordinate through messages.

**Why "engraving."** When the agent starts through this bridge it sees the model's underlying API (Claude or the codex GPT-5 line) and recognises pi as the harness — pi's own system/developer message says so, and a direct (non-bridged) pi session would already make that visible. What the agent does **not** know without further help is which **bridge layer** sits between the model and pi: that the prompt arrived *through pi-shell-acp specifically*, with this MCP set, this tool boundary, this operator-config overlay, and not through some other path. The engraving (six lines in [`prompts/engraving.md`](./prompts/engraving.md)) names that bridge layer and tells the agent: "you are not alone — read your MCP servers to see what's connected." Each backend gets the engraving at the highest stable identity-carrier surface it exposes — for Claude that's the system prompt itself (string-form preset replacement), for Codex it's the codex `developer_instructions` config slot — and the operator's personal config under `~/.claude/` / `~/.codex/` stays out of the bridge's view via narrow whitelist overlays. Without the engraving, the agent has to guess at the bridge layer above pi. With it, the agent reads it.

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

Each prior approach contributed to the understanding that led here. `pi-shell-acp` chose ACP because it is the protocol path used by Zed's Claude Code integration, not a proxy or transcript-scraping workaround.

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

Claude keeps its model/API identity, but pi-shell-acp replaces the Claude Code preset with the six-line engraving via `_meta.systemPrompt = <string>`. The hard-wired Claude Agent SDK identity prefix remains; pi-shell-acp controls only the operating surface above it.

| Field | Default | Purpose |
|-------|---------|---------|
| `tools` | `["Read", "Bash", "Edit", "Write"]` | Match pi's declared 4-tool baseline. `Skill` is auto-added when `skillPlugins` is non-empty. |
| `settingSources` | `[]` | Do not inherit user/project/local Claude Code settings unless explicitly opted in. |
| `strictMcpConfig` | `true` | Only `piShellAcpProvider.mcpServers` reaches the backend. |
| `skillPlugins` | `[]` | Explicit Claude plugin roots (`.claude-plugin/plugin.json` + `skills/*/SKILL.md`). |
| `permissionAllow` | `["Read(*)", "Bash(*)", "Edit(*)", "Write(*)", "mcp__*"]` | Allow the declared tool surface without flipping the operator's native Claude Code defaults. |
| `disallowedTools` | deferred Claude Code tool set | Keep deferred tools (`Task*`, `Cron*`, `Web*`, etc.) from appearing outside pi's declared surface. |

`CLAUDE_CONFIG_DIR` points to a pi-owned whitelist overlay (`~/.pi/agent/claude-config-overlay/`) so auth/runtime state remains available while operator memory, hooks, agents, history, local settings, and project memory stay hidden by default. An explicitly exported `CLAUDE_CONFIG_DIR` wins.

#### Operating-surface contract — Codex backend

Codex has no `_meta.systemPrompt` lane, so pi-shell-acp uses codex-rs `-c` flags. The engraving is delivered as `-c developer_instructions="<...>"`.

| Flag / setting | Default | Purpose |
|---|---|---|
| `approval_policy` | `never` | Autonomous pi-style operation. |
| `sandbox_mode` | `danger-full-access` | Let pi skills read workspace-external state when needed. |
| `model_auto_compact_token_limit` | `i64::MAX` | Disable silent codex auto-compaction. |
| `web_search` | `disabled` | Use pi's explicit web surfaces instead. |
| `codexDisabledFeatures` | `image_generation`, `tool_suggest`, `tool_search`, `multi_agent`, `apps`, `memories` | Fail closed on tools/memory surfaces that would bypass pi's declared MCP/tool model. |

`PI_SHELL_ACP_CODEX_MODE=auto|read-only` narrows the default mode; invalid values throw. `codexDisabledFeatures: []` opts out of the fail-closed feature gate and emits a warning.

`CODEX_HOME` and `CODEX_SQLITE_HOME` point to `~/.pi/agent/codex-config-overlay/`. The overlay keeps auth/runtime entries and codex state DBs, but hides operator history, rules, top-level `AGENTS.md`, personal config, sessions, logs, and memories. Exported `CODEX_HOME` / `CODEX_SQLITE_HOME` win.

Known codex limit: some native tools are registered by codex-rs without config gates (`update_plan`, `request_user_input`, `view_image`, MCP resource readers). pi-shell-acp documents this mismatch; closing it requires codex-rs changes.

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
| `mcp/pi-tools-bridge/` | MCP adapter (agent-facing): `entwurf`, `entwurf_resume`, `entwurf_send`, `entwurf_peers` |
| `mcp/session-bridge/` | Claude Code ↔ pi session bridge (wire-compatible with entwurf-control) |

The same surface is split between agent-callable MCP tools and operator-callable slash commands. Both share the same `~/.pi/entwurf-control/` socket directory; the agent path is auto-attached, the slash path is an explicit `--entwurf-control` opt-in:

| Surface | Audience | Examples |
|---|---|---|
| MCP tools (above) | the agent (LLM tool calls) | `entwurf_send`, `entwurf_peers` |
| Slash commands (require `--entwurf-control`) | the operator (interactive pi session) | `/entwurf <task>`, `/entwurf-status`, `/entwurf-sessions` (lists peers with cwd / model / idle), `/entwurf-send <index\|sessionId> <message>` |

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

Rule: **no silent rewrite**. pi-shell-acp cancels every pi-side compaction trigger through `session_before_compact` unless the operator starts the process with `PI_SHELL_ACP_ALLOW_COMPACTION=1`.

Backend guards mirror that policy:

- Claude Code: `DISABLE_AUTO_COMPACT=1` and `DISABLE_COMPACT=1`
- Codex: `-c model_auto_compact_token_limit=9223372036854775807`

The footer uses the ACP backend's `usage_update.used / size`, not pi's visible-transcript estimate. That number can be larger than the visible chat because the backend counts its own prompt, tools, cache, and session state. Each turn also emits `[pi-shell-acp:usage] ...` with raw component values and whether the meter came from `usage_update` or the fallback component sum.

Operationally: when the backend window is near its limit, choose a visible action — clear, opt into compaction, switch to a wider-context model, or in 0.5.0 use recap-as-new-question.

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

The maintainer uses pi-shell-acp for most pi work unless a task needs a different harness. Public examples are ordinary working repos, not benchmarks.

- [junghan0611/legoagent-config](https://github.com/junghan0611/legoagent-config) — a small Lego/child-oriented project that also serves as a low-stakes daily testbed for pi-shell-acp.

## Roadmap

- **0.4.x / 0.4.2 — Documentation calibration.** Align README and AGENTS.md with VERIFY.md's Evidence Levels and Claims Ledger. Keep strong claims, but label what is design intent, what is verified, and what still needs L3–L5 evidence. Long-term: publish session-level verification data (see [pi-share-hf](https://github.com/badlogic/pi-share-hf) as a reference pipeline) so ACP-bridge behaviour can be reviewed at the session-record level, not only as narrative.
- **0.5.0 — Visible recap-as-new-question.** Replace silent compaction with explicit recap as the long-session strategy. Long sessions should end with a structured, operator-visible recap that seeds a fresh session, rather than a silently rewritten transcript. The design must specify who generates the recap, where it is stored, how the old ACP mapping is closed, and how VERIFY.md proves no hidden transcript hydration occurred.
- **0.6.0 — OpenClaw native provider.** Drop-in like ACPx — built-in provider, no extra ACP command surface, no entwurf needed (OpenClaw uses pi natively, so the bridge only has to wire the provider; the rest is pi's existing tool model).

## Verification surfaces

Two complementary documents, not redundant:

- **[VERIFY.md](./VERIFY.md)** — agent-driven. One ACP-bridged identity runs the script against another and records what it sees. Carries the Evidence Levels L0–L5 rung ladder and a Claims Ledger so each claim is parked at the rung it has actually reached.
- **[BASELINE.md](./BASELINE.md)** — operator-driven. Junghan runs the interview himself (no agent in the verifier seat) and the result is recorded. Companion to VERIFY.md — VERIFY exercises agent↔agent symmetry; BASELINE keeps a human's direct read on the same surfaces.

Use both. Either one alone leaves a blind spot the other closes.

## Status

Public, active development. The maintainer uses pi as his primary coding environment; this ACP bridge is working code, but it is still being proven through daily use.

## License

MIT
