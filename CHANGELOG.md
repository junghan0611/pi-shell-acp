# Changelog

All notable changes to this project will be documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The repo uses semver.

## Unreleased

### Internal — fence consolidation

Every `.ts` source file in the repo is now reached by `pnpm typecheck`. Previously two surfaces lived outside the fence:

- `pi-extensions/entwurf-control.ts` was excluded from the root tsconfig. The exclude hid type drift introduced by the 0.5.0 sessionId-only refactor: residual `sessionName` / `session.name` reads in `renderCall`, `entwurf_peers` description, and peers output; `pi.on("session_switch", ...)` and `pi.on("session_fork", ...)` handlers registered against event names that pi-coding-agent 0.70.x does not expose (`session_start{reason: "fork" | "new" | "resume"}` covers them); a renderer reading `result.isError` against an `AgentToolResult<T>` type that does not declare it (the framework spreads it onto the result at runtime); a typebox-version mismatch (`@sinclair/typebox` 0.34 mixed with pi-coding-agent's typebox 1.x via `StringEnum`) silently widening parameters to `unknown`; a dead `getMessagesSinceLastPrompt` helper.
- `mcp/` was excluded wholesale. Both bridges run via `node --experimental-strip-types` and were never type-checked anywhere. Inside, `mcp/session-bridge/src/index.ts` still resolved targets via `<sessionName>.alias` symlinks and a name scan — the same alias surface that `entwurf-control.ts` declared dead since 0.5.0, but on a different physical directory and a different audience (humans operating Claude Code, not AI peers).

Both surfaces are now inside the fence and the invariants are reconciled:

- Root `tsconfig.json` stays emit-capable so `./run.sh check-models` can keep tsc-emitting the project entry into `.tmp-verify-models/` for runtime introspection. A new `mcp/tsconfig.json` extends the root and adds the strip-types-runtime concessions (`allowImportingTsExtensions`, `noEmit`); `pnpm typecheck` runs both as a sequential pair. `AGENTS.md` § Typecheck Boundary documents the new shape and pins the rule that no `.ts` source file may sit outside both configs.
- `pi-extensions/entwurf-control.ts`: dead handlers (`session_switch`, `session_fork`) and dead helper (`getMessagesSinceLastPrompt`) removed; defensive runtime cast at the post-exhaustive-switch fallback; `result.isError` access replaced with a documented runtime cast that reads the framework's spread-injected field plus a `details.error` fallback (with the `||` vs `?:` precedence bug fixed); residual `sessionName`/`session.name` reads removed at the addressing surfaces; `Type` imported from `@mariozechner/pi-ai` to align the typebox universe with `StringEnum` and with what `pi.registerTool` consumes; `execute(params)` and `renderCall(args)` annotated with an explicit `EntwurfSendParams` type so the schema (runtime) and the type (compile-time) describe the same contract on both sides — schema-to-type inference is then bypassed and TS2589 cannot resurface. The two concrete revisit conditions for collapsing back to schema-inferred params are documented inline.
- `pi-extensions/entwurf.ts` and `package.json` finish the typebox single-source: `Type` is imported from `@mariozechner/pi-ai` here too, and `@sinclair/typebox` is removed as a direct dependency. pi-coding-agent's typebox 1.x continues to flow in transitively.
- `mcp/session-bridge/`: the alias-claim path in `createAlias` is now atomic — `fs.symlink` into a unique tmp path, then `fs.rename` onto the alias path. POSIX rename atomically replaces the destination, closing the unlink-then-symlink window where two concurrent same-name starts could both observe "no alias" and both write one. The file header documents why the human-aliased addressing surface is intentionally kept here while entwurf addressing is sessionId-only — different audience, different cost/benefit, no polling timer, fall-through to live-session scan if the alias is stale.

Why this is in the changelog and not folded into a feature release: the previous "typecheck green" state was green only because the broken files were outside the fence. Closing the fence forced every silent invariant violation to surface and be reconciled. The maintainer treats fence breaches as latent bugs, not as test-coverage choices, and the public log should reflect that.

## 0.4.5 — 2026-04-29

### Fixed

- **Restored pi / AGENTS context for ACP backends without growing the system-prompt carrier.** `appendSystemPrompt: false` remains the safe default: Claude still receives only the short engraving through `_meta.systemPrompt`, and Codex still receives engraving through `developer_instructions`. The rich pi context now rides a one-shot first user-message augment so both backends actually receive the bridge identity narrative, pi operating context, `~/AGENTS.md`, `cwd/AGENTS.md`, and date/cwd.
- **Avoided Claude Code OAuth "extra usage" failures from large custom system prompts.** The pi context no longer needs to be inserted into Claude's `_meta.systemPrompt = <string>` carrier, which had caused subscription sessions to be classified as metered usage when the carrier grew beyond the SDK-default shape.
- **Made entwurf-spawned ACP sessions receive the home context without duplicating project AGENTS.** Entwurf tasks already carry `cwd/AGENTS.md` in `<project-context ...>` tags; the bridge now detects that marker, removes only the duplicate cwd AGENTS section from the first-user augment, and preserves `~/AGENTS.md`, bridge narrative, pi base context, and date/cwd.
- **Failed loudly when configured AGENTS files cannot be read.** Missing AGENTS files are still allowed, but if `~/AGENTS.md` or `cwd/AGENTS.md` exists and cannot be read, bootstrap throws instead of silently starting a context-poor agent.
- **Separated capability descriptions from concrete tool names.** The first-user augment now tells agents to treat the actual callable tool schema as source of truth. Native pi, Claude ACP, and Codex ACP expose different tool names for similar capabilities (`read/bash/edit/write`, `Read/Bash/Edit/Write/Skill`, `exec_command/apply_patch/...`), so agents must not claim a tool exists only because AGENTS.md or the augment mentions it.
- **Fixed prompt hygiene around first-message prepends.** The augment is separated from the original user prompt with a blank line, preventing `Current working directory: ...<project-context ...>` concatenation in entwurf first prompts.

### Changed

- **Engraving is now an optional operator personal surface.** `prompts/engraving.md` ships as a minimal placeholder (`각인이라고 여기`); empty or missing engraving files are skipped. Bridge identity and operating context moved to the first-user augment.
- **Shared the `<project-context` wire marker through `protocol.ts`.** Entwurf generation and ACP-side de-dup detection now import the same dependency-free constant, keeping the wire-format marker single-sourced across root emit and MCP strip-types execution paths.

### Verification

- Re-ran paired identity interviews against Claude ACP and Codex ACP. Both now recognize pi-shell-acp, receive home/project AGENTS context, and distinguish prompt/context claims from actual callable tool schemas. Entwurf resume against a Sonnet sibling confirmed both `~/AGENTS.md` and project AGENTS context were retained across resume.

## 0.4.1 — 2026-04-29

Patch release closing a release blocker carried since 0.3.0 and adding the missing direct human-facing entwurf surface, plus removing the alias addressing layer the operating model has outgrown.

### Fixed

- **Entwurf extensions actually load.** `pi-extensions/entwurf.ts` and `pi-extensions/entwurf-control.ts` have lived in the repo since 0.3.0 but were never wired into `package.json`'s `pi.extensions` array, so neither the `--entwurf-control` flag nor the `/entwurf` / `/entwurf-status` / `/entwurf-sessions` slash commands actually loaded. The MCP bridge expected sockets at `~/.pi/entwurf-control/`, which an unloaded control extension never creates — leaving the entwurf surface documented in README/AGENTS.md effectively dead at runtime. Both entries are now in `pi.extensions`.

### Added

- **`/entwurf-sessions`** now surfaces cwd, model id, and idle state per live session via a new `get_info` RPC command, with `[N]` indices for direct addressing and per-session error rows when an individual peer fails to respond. The displayed list is cached so `/entwurf-send` can address by index.
- **`/entwurf-send <index|sessionId> <message>`** — the previously missing interactive surface for a human operator to message another live entwurf session directly. Defaults to `follow_up` mode and auto-attaches `<sender_info>` so the receiving side can reply via the `entwurf_send` MCP tool. The MCP `entwurf_send` tool path remains the agent-facing surface (errors crash the call so the agent cannot paper over a misroute); the new slash command is the human surface and reports failures as ordinary notifications.
- **`get_info` RPC command** on the entwurf control socket — returns `sessionId`, `cwd`, `model { id, provider }`, and `idle` for the serving session. Used by `/entwurf-sessions` enrichment; reusable by future tooling.
- **`gcStaleSockets()`** runs once per `startControlServer()` and cleans dead `.sock` entries from `~/.pi/entwurf-control/`. Pre-0.4.1 `.alias` symlinks left in the directory by older builds are also swept on encounter, retiring the GC TODO at `pi-extensions/entwurf-control.ts:213`.

### Removed (BREAKING — entwurf-control surface only)

The alias layer — `<sessionName>.alias` symlinks under `~/.pi/entwurf-control/` mirroring pi's `SessionManager.sessionName` via a 1s `setInterval` polling timer — is removed entirely. With per-session compaction disabled, the operating model is short-lived sessions ending in recap+new (see roadmap), so a human-friendly alias has little time to accumulate value, and the polling timer was the sole reason a kernel-driven socket-push design needed wall-clock work at all. The three race surfaces it carried — concurrent `syncAlias`, timer-vs-shutdown, symlink-vs-listener — are now structurally absent.

- `entwurf_send` MCP tool: `target` parameter renamed to `sessionId`; alias resolution removed. Use `entwurf_peers` to discover live ids.
- `entwurf_peers` MCP response: `name` and `aliases` fields removed from each session entry.
- `entwurf_send` extension tool (in-process): `sessionName` parameter removed; `sessionId` is now required.
- `--entwurf-session` CLI flag: only accepts a sessionId (UUID).
- `/entwurf-sessions` output drops the parenthetical `(alias)` label.
- `/entwurf-send`: `<alias>` form removed; `<index|sessionId>` only.

This change is independent of agent-config's `--session-control` extension under `~/.pi/session-control/` (its ingested copy of the alias surface is intentionally kept — different cost/benefit, no polling timer, no race surface) and of the bundled `mcp/session-bridge/` MCP (Claude Code-side; its `SESSION_NAME` alias is set once from cwd at `start.sh` and is the stable identity surface that side needs).

### Identity verification

A four-case identity interview was captured against 0.4.0 + this patch — OpenRouter Sonnet, pi-shell-acp Sonnet, native Codex, pi-shell-acp Codex. Both pi-shell-acp cases recognize `pi-shell-acp` as the bridge surface and enumerate `mcp__pi-tools-bridge__*` and `mcp__session-bridge__*` correctly. The two non-bridge cases honestly report that the entwurf MCP is "described in AGENTS.md but not in my schema" — the boundary is real and the agent sees it. The transcripts are being moved to BASELINE.md as part of 0.4.x, alongside the longer-term plan to publish session-level verification data (see roadmap).

## 0.4.0 — 2026-04-28

PI-native identity carriers for both ACP backends — Claude via system-prompt replacement, Codex via codex `Config` `developer_instructions` — with whitelist overlays isolating operator config, memory, sessions, rules, history, and (codex-specific) the SQLite thread/memory state DB. The model API itself is unchanged on each side; pi-shell-acp now owns everything above the model's minimum identity prefix and below the backend authentication.

### Changed

- **Engraving carrier — Claude.** Previously delivered via `_meta.systemPrompt.append`, additive on top of the claude_code preset. Now delivered via `_meta.systemPrompt = <engraving string>` (claude-agent-acp `acp-agent.ts:1685`, sdk.d.ts:1695), which makes claude-agent-acp pass the string directly into the SDK's `Options.systemPrompt` slot — full preset replacement. The claude_code preset's `# auto memory` guidance, per-cwd MEMORY.md path advertisement, working-directory section, git-status section, and todo-handling guidance all drop out of the system prompt. The engraving sits directly above the SDK's hard-wired minimum identity prefix (_"You are a Claude agent, built on Anthropic's Claude Agent SDK."_), which is the boundary pi-shell-acp deliberately respects. Verified by interview against the Claude backend (BASELINE.md, first run): the agent correctly identifies as a PI-native operating surface on top of the Claude API, refuses to claim auto-memory it does not have, and asks before running side-effecting capability checks.
- **Engraving carrier — Codex.** Previously delivered as a first-prompt `ContentBlock` prepend, which lands at user-message authority. Now delivered as `-c developer_instructions="<engraving>"` at codex-acp child spawn time, which materializes inside the codex `developer` role between the binary's `permissions` / `apps` / `skills` instruction blocks. codex-acp does not honor `_meta.systemPrompt` (verified against the Rust source — `codex-acp/src/thread.rs` `meta.get(...)` call sites all target MCP tool approval keys, none target prompt-level surfaces); `developer_instructions` is the highest stable identity carrier the codex stack offers. Structurally one config layer below the Claude side's preset replacement, but equivalent in authority intent. The new carrier participates in `bridgeConfigSignature` / session compatibility, so changing the engraving forces a fresh codex-acp spawn — reusing an existing child against a stale carrier would surface the previous identity to the model.
- **Compaction toggle no longer affects identity isolation.** Previously, `PI_SHELL_ACP_ALLOW_COMPACTION=1` set the entire `bridgeEnvDefaults` block to `undefined`, which dropped `CLAUDE_CONFIG_DIR` / `CODEX_HOME` / `CODEX_SQLITE_HOME` along with the Claude compaction-guard pair. That silently turned operator config inheritance back on the moment compaction was allowed. The toggle now strips only the compaction-guard env keys (`DISABLE_AUTO_COMPACT`, `DISABLE_COMPACT`); identity-isolation env stays regardless. Identity isolation is an invariant; the compaction knob is policy.

### Added

- **Whitelist overlay — Claude.** `~/.pi/agent/claude-config-overlay/` is now built from a fixed allowlist instead of mirroring `~/.claude/` minus `settings.json`. Author-controlled `settings.json` (`permissions.defaultMode = "default"`, `autoMemoryEnabled: false`); passthrough symlinks for `auth.json`, `cache`, `debug`, `session-bridge`, `session-env`, `shell-snapshots`, `skills`, `stats-cache.json`, `statsig`, `telemetry`; overlay-private empty `projects/` and `sessions/`; binary-managed `.claude.json` and `backups/`. Anything else (`CLAUDE.md`, `hooks/`, `agents/`, `todos/`, `tasks/`, `history.jsonl`, `settings.local.json` carrying personal env / GitHub PAT, `plugins/` operator enablement, ...) is intentionally not in the overlay. Stale entries from earlier blacklist-style overlays are wiped on first bootstrap with this code.
- **Whitelist overlay — Codex.** Narrower than Claude because codex's leak surfaces run deeper. `CODEX_HOME` *and* the new `CODEX_SQLITE_HOME` env both pinned to `~/.pi/agent/codex-config-overlay/` so the codex thread/memory state DB cannot drift outside the overlay through env or future code paths. Author-controlled `config.toml`; passthrough symlinks for nine entries (`auth.json`, install metadata, non-data caches, `skills`); overlay-private empty `memories/`, `sessions/`, `log/`, `shell_snapshots/`; binary-managed `state_5.sqlite{,-shm,-wal}` + `logs_2.sqlite{,-shm,-wal}` (both DB groups). Operator entries hidden by the whitelist: `history.jsonl`, `rules/` (codex execution policy, not narrative memory), `AGENTS.md` (auto-loaded by `codex-rs/agents_md.rs` as user instructions), the operator's personal `config.toml` fields. Pre-migration overlays carrying stale operator-side symlinks for the binary-managed entries get those symlinks stripped on first bootstrap with this code, so codex re-initializes fresh state.
- **Three-layer codex memory isolation.** `codexDisabledFeatures` default gains `memories` so codex stops loading operator memory entries into the developer-role context. Two more layers pinned at launch via the new `CODEX_OPERATOR_ISOLATION_ARGS` group: `memories.generate_memories=false`, `memories.use_memories=false`, `history.persistence="none"`. Plus the overlay's empty `memories/` directory itself. Defense in depth against a future codex build flipping the feature gate or renaming the keys.
- **`resolveBridgeEnvDefaults(backend, { allowCompaction })` exported helper.** Single source of truth for how the spawned child's env defaults compose with the compaction toggle. Routed through `createBridgeProcess` and exercised directly by `check-backends` so the compaction-vs-isolation separation is pinned at unit-test time, not just at production startup.
- **`tomlBasicString(value)` helper** for the Codex carrier. JSON's escape rules are a strict subset of TOML basic-string escapes (`\\`, `\"`, `\n`, `\r`, `\t`, `\uXXXX`), so `JSON.stringify(value)` produces a TOML-valid quoted form usable directly as the value half of `-c developer_instructions=<...>`. Used by both the spawn-array path and the `CODEX_ACP_COMMAND` shell-override path.
- **`BASELINE.md`** — paired-language identity-check interview (Korean + English) any human operator can run against a fresh pi-shell-acp session, plus history entries for the first PI-native baseline runs on both backends.

### Removed

- `buildCodexBootstrapPromptAugment` and the codex adapter's `buildBootstrapPromptAugment` handler. The first-prompt `ContentBlock` prepend was the previous codex carrier; `developer_instructions` replaces it. The interface point on `AcpBackendAdapter` remains for future backends that lack a higher-authority carrier.

### Verification

`check-backends` grew from 52 → 110 assertions across the two PI-native commits and the migration / compaction-isolation fix that followed. The new invariants:

- TOML escape contract for `developer_instructions` (presence/absence based on input, multi-line + embedded-quote escaping).
- Claude overlay leak canaries — operator-side `MEMORY.md` and `hooks/` must not be reachable through the overlay.
- Codex overlay leak canaries — operator-side memory, sessions data, `history.jsonl`, `rules/`, `AGENTS.md`, `log/`, `shell_snapshots/`, and the four state/logs DB files (state_5.sqlite + WAL/SHM, logs_2.sqlite + WAL/SHM) must not be reachable through the overlay.
- Migration regression — pre-migration overlays carrying stale operator-side symlinks for binary-managed entries get those symlinks stripped on first run with the new code.
- `resolveBridgeEnvDefaults` — Claude with compaction allowed strips compaction-guard env but keeps `CLAUDE_CONFIG_DIR`; Codex with compaction allowed keeps both `CODEX_HOME` and `CODEX_SQLITE_HOME` (codex's compaction guard is a launch-arg threshold, not env).
- Idempotence on second call.

### Notes for upgraders

The first session bootstrap after upgrading from 0.3.x will silently migrate the existing overlay shape. Stale symlinks carrying operator data — including, on the codex side, symlinks pointing at the operator's real `state_5.sqlite*` thread/memory state DB — are wiped automatically. The upgrade path needs no manual intervention. After the first session, `~/.pi/agent/{claude,codex}-config-overlay/` should match the whitelist shape described above; if it doesn't, the migration ran in a different process and the overlay rebuild on the next bootstrap will converge.

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
