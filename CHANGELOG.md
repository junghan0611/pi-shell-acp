# Changelog

All notable changes to this project will be documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The repo uses semver.

## Unreleased

## 0.3.1 — 2026-04-28

### Added

- **Operator warning when `codexDisabledFeatures: []` is set explicitly.** The empty-array case opts the codex backend fully out of bridge feature gating (codex native `multi_agent` / `apps` / `image_generation` / `tool_suggest` / `tool_search` all become callable), which differs from key-absent (default `DEFAULT_CODEX_DISABLED_FEATURES` applies). The two cases were conflated in agent-config 0.2.x as "redundant defense-in-depth" — the `[]` was originally a workaround for the 0.2.1 `params.codexDisabledFeatures.spread` crash, then survived the 0.2.2 nullish-guard fix and silently flipped the codex tool surface from fail-closed to fail-open. Bridge now emits a one-shot stderr warning on first bootstrap whenever explicit `[]` is observed (`[pi-shell-acp:warn] codexDisabledFeatures=[] in settings.json explicitly opts out ... To restore the fail-closed default, remove the codexDisabledFeatures key`). Throttled to once per process — does not repeat on prompt or model switch. Key-absent and partial-disable cases stay silent. Surfaced after a Codex identity-check session reported `spawn_agent` / `mcp__codex_apps__github_*` as available native tools on a fresh 0.3.0 install where the operator's `~/.pi/agent/settings.json` carried the legacy `[]` knob.

## 0.3.0 — 2026-04-27

### Fixed

- **claude-agent-acp child no longer silently exits when the SDK's auto-detect resolves the wrong libc variant.** claude-agent-acp 0.31.0 (`dist/acp-agent.js:1298`) reads `process.env.CLAUDE_CODE_EXECUTABLE` only and ignores the `_meta.claudeCode.options.pathToClaudeCodeExecutable` pi-shell-acp passes. NODE_PATH (set by the pnpm-installed pi-coding-agent wrapper) hoists both musl and glibc variants of `@anthropic-ai/claude-agent-sdk-linux-<arch>-*`; the SDK's `[musl, glibc]` resolution order picks musl first and spawn fails with ENOENT on glibc hosts → child silent exit → "Internal error" after retry. pi-shell-acp now sets `CLAUDE_CODE_EXECUTABLE` in the child env from `resolveClaudeCodeExecutable()` (libc-aware). Operator's exported var still wins (process.env spread last). Surfaced as "Internal error" on oracle ARM aarch64.

- **`~/.pi/agent/entwurf-targets.json` auto-symlinked at install time.** `pi-extensions/lib/entwurf-core.ts:45` reads `~/.pi/agent/entwurf-targets.json`, but the package shipped the canonical version only at `<install_dir>/pi/entwurf-targets.json`. Without manual setup, any `entwurf` tool call threw `EntwurfRegistryError` (lazy — no surface during plain `pi --model ...` runs but blocks delegation immediately). `run.sh install_local_package` now creates the symlink idempotently and preserves any operator override (file or differently-targeted symlink left untouched).

## 0.2.2 — 2026-04-27

### Fixed

- `ensureBridgeSession` no longer crashes with `TypeError: params.codexDisabledFeatures is not iterable` when callers omit the `codexDisabledFeatures` field. The 0.2.0 introduction of the `codexDisabledFeatures` knob added required spreads in `createBridgeProcess` and the reuse path, but `loadProviderSettings`'s default fallback only covers callers that go through `index.ts` (i.e. the production `pi --model ...` path). Smoke embed scripts in `run.sh` (and any third-party caller) bypass that fallback and were exposed to the spread crash. Both spread sites now normalize via `params.codexDisabledFeatures ?? DEFAULT_CODEX_DISABLED_FEATURES`, matching what `loadProviderSettings` would have applied. Universal — any backend (claude, codex), any caller path. Surfaced as "Internal error" in pi sessions on a fresh consumer install.
- `run.sh` smoke embed scripts (`smoke-claude/codex`, `smoke-cancel`, `smoke-model-switch`) now declare `codexDisabledFeatures: []` explicitly so caller intent is visible at the embed site, not only via the `acp-bridge.ts` fallback.

### Docs

- `AGENTS.md` § Entwurf: cross-reference the resident-side naming pair `MITSEIN.md` in agent-config (Mitsein/Entwurf as Heidegger pair — pi-shell-acp owns the entwurf side, resident conventions live in agent-config). Also clarify the bare-model auto-resolution rule in the target-registry bullet.

## 0.2.1 — 2026-04-27

### Fixed

- Consumer install no longer breaks when `husky` is not installed (dev-only dep). The `prepare` script falls through with `|| true`, so `pi install git:github.com/junghan0611/pi-shell-acp` works on machines that don't have husky. Previously failed with `husky: command not found (sh: line 1, exit 127)` on consumer install paths (e.g. Oracle).

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
