# Changelog

All notable changes to this project will be documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The repo uses semver.

## Unreleased

## 0.2.0 — 2026-04-27

First public release. Used daily by the maintainer; not promised to work elsewhere yet.

### ACP bridge

- Provider `pi-shell-acp` registers with pi. Models route to backends by curated allowlist (`claude-sonnet-4-6` / `claude-opus-4-7` → Claude, `gpt-5.x` from `openai-codex` → Codex), with prefix fallback for non-curated IDs.
- Bootstrap order is `resume > load > new`, with `pi:<sessionId>` persisted under `~/.pi/agent/cache/pi-shell-acp/sessions/`.
- Per-turn `usage_update` (or `PromptResponse.usage` fallback) drives the pi footer context meter; the bridge does not maintain a separate meter.

### Operating-surface contract

- Claude side: `tools` defaults to `[Read, Bash, Edit, Write]` (auto-adds `Skill` when `skillPlugins` is non-empty). `disallowedTools` default blocks the SDK's deferred-tool advertisement (`Cron*`, `Task*`, `Worktree*`, `EnterPlanMode`/`ExitPlanMode`, `Monitor`, `NotebookEdit`, `PushNotification`, `RemoteTrigger`, `WebFetch`, `WebSearch`, `AskUserQuestion`). `settingSources: []` + `strictMcpConfig: true` by default. `permissionAllow` wildcards thread into `Options.settings.permissions.allow`.
- Codex side: `approval_policy=never` + `sandbox_mode=danger-full-access` + `model_auto_compact_token_limit=i64::MAX` pinned at every launch. `web_search="disabled"` and `tools.view_image=false` pinned. `codexDisabledFeatures` (settings.json) materializes as `-c features.<key>=false` flags; defaults to `image_generation`, `tool_suggest`, `tool_search`, `multi_agent`, `apps`. Operator can opt fully out with `[]` or override.
- Both backends launched with config overlays (`CLAUDE_CONFIG_DIR=~/.pi/agent/claude-config-overlay/`, `CODEX_HOME=~/.pi/agent/codex-config-overlay/`) — pi-authored config file + symlinks for every other entry, idempotent rebuild on each launch. Operator's exported env wins.

### Compaction policy

- Host: `session_before_compact` returns `{cancel: true}` for every pi compaction trigger (silent overflow recovery, threshold compaction, explicit-error overflow, manual `/compact`). Opt out with `PI_SHELL_ACP_ALLOW_COMPACTION=1`.
- Backend: `DISABLE_AUTO_COMPACT=1` + `DISABLE_COMPACT=1` (Claude), `model_auto_compact_token_limit=i64::MAX` (Codex).

### Entwurf

- Sync + async spawn (`pi-extensions/entwurf.ts`), shared registry + identity preservation (`lib/entwurf-core.ts`), Unix-socket control plane (`entwurf-control.ts`, ingested from Armin Ronacher's `agent-stuff` under Apache 2.0).
- Spawn target allowlist at `pi/entwurf-targets.json`.
- MCP adapter `pi-tools-bridge` exposes `entwurf`, `entwurf_resume`, `entwurf_send`, `entwurf_peers`. Send is fire-and-forget.
- `mcp/session-bridge/` carries Claude Code ↔ pi session messages (`list_sessions`, `send_message`, `receive_messages`, `session_info`).

### Engraving

- Short additive text from `prompts/engraving.md`, delivered via `_meta.systemPrompt.append` (Claude) or first-prompt `ContentBlock` prepend (Codex). `{{backend}}` and `{{mcp_servers}}` substituted at bootstrap. The engraving appends to the backend's native system prompt; it does not replace it.

### Tooling

- `./run.sh` covers install, smoke (Claude / Codex / both), resume verification, MCP bridge check, sentinel, session-messaging.
- `check-backends` (52 assertions) gates launch flag composition, override paths, and `codexDisabledFeatures` empty / partial cases.
- `check-dep-versions` catches version-pin drift between `package.json` and `run.sh`.
- Husky pre-commit hook runs typecheck + check-backends + check-models + check-mcp + check-dep-versions; skipping requires explicit acknowledgement.
- Release flow lives at `.pi/prompts/make-release.md` + `scripts/release.sh`.

### Pinned versions

- `@agentclientprotocol/claude-agent-acp@0.31.0`
- `@zed-industries/codex-acp@0.12.0`
- `@agentclientprotocol/sdk@0.20.0`
