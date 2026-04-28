import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { McpServer } from "@agentclientprotocol/sdk";
import {
	type AssistantMessage,
	type AssistantMessageEventStream,
	type Context,
	calculateCost,
	createAssistantMessageEventStream,
	getModels,
	type Model,
	type SimpleStreamOptions,
} from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import {
	type AcpBackend,
	type ClaudeSettingSource,
	cancelActivePrompt,
	cleanupBridgeSessionProcess,
	closeBridgeSession,
	DEFAULT_CODEX_DISABLED_FEATURES,
	describeBridgeSession,
	ensureBridgeSession,
	getBridgeErrorDetails,
	type McpServerInputMap,
	normalizeMcpServers,
	sendPrompt,
	setActivePromptHandler,
} from "./acp-bridge.js";
import { loadEngraving } from "./engraving.js";
import { type AcpPiStreamState, applyBridgePromptEvent, finalizeAcpStreamState } from "./event-mapper.js";

const PROVIDER_ID = "pi-shell-acp";
const REGISTERED_SYMBOL = Symbol.for("pi-shell-acp:registered");

function debugLoggingEnabled(): boolean {
	const value = process.env.PI_SHELL_ACP_DEBUG?.trim().toLowerCase();
	return value === "1" || value === "true" || value === "yes";
}

function logBridgeDiagnostic(label: string, payload: Record<string, unknown>): void {
	if (!debugLoggingEnabled()) return;
	console.error(`[pi-shell-acp] ${label} ${JSON.stringify(payload)}`);
}

function isRegisteredOnRuntime(pi: ExtensionAPI): boolean {
	return Boolean((pi as unknown as Record<PropertyKey, unknown>)[REGISTERED_SYMBOL]);
}

function markRegisteredOnRuntime(pi: ExtensionAPI): void {
	Object.defineProperty(pi as object, REGISTERED_SYMBOL, {
		value: true,
		configurable: false,
		enumerable: false,
		writable: false,
	});
}
const GLOBAL_SETTINGS_PATH = join(homedir(), ".pi", "agent", "settings.json");

type ProviderSettings = {
	backend?: AcpBackend;
	appendSystemPrompt?: boolean;
	settingSources?: ClaudeSettingSource[];
	strictMcpConfig?: boolean;
	showToolNotifications?: boolean;
	mcpServers?: McpServerInputMap;
	/** Built-in Claude Code tools to expose. Defaults to pi baseline (Read/Bash/Edit/Write). Only consumed by the Claude backend; codex ignores it. */
	tools?: string[];
	/** Absolute paths to Claude Code plugin directories. Each path is injected as `{ type: "local", path }` into the Claude SDK `plugins` option so skills can be delivered explicitly without opening `settingSources`. Claude-only. */
	skillPlugins?: string[];
	/** Wildcard rules passed to the SDK as `Options.settings.permissions.allow`. Defaults to allowing the pi-baseline tools and any MCP. Claude-only. */
	permissionAllow?: string[];
	/** Tool names passed to the SDK as `Options.disallowedTools`. Defaults to the SDK's deferred-tool set (Cron+Task+Worktree+PlanMode families plus WebFetch, WebSearch, Monitor, PushNotification, RemoteTrigger, NotebookEdit, AskUserQuestion) so they cannot leak past the explicit `tools` filter via the SDK's deferred-advertisement surface. Set to `[]` to opt out entirely. Claude-only. */
	disallowedTools?: string[];
	/** codex-rs feature keys to disable at codex-acp launch via `-c features.<key>=false`. Defaults to `DEFAULT_CODEX_DISABLED_FEATURES` (image_generation, tool_suggest, tool_search, multi_agent, apps) so the codex tool surface aligns with pi's advertised baseline. Set to `[]` to opt out entirely. Codex-only — Claude ignores it. Mirror of `disallowedTools` on the codex side. */
	codexDisabledFeatures?: string[];
};

type ResolvedProviderSettings = {
	backend: AcpBackend;
	backendSource: "explicit" | "inferred";
	appendSystemPrompt: boolean;
	settingSources: ClaudeSettingSource[];
	strictMcpConfig: boolean;
	showToolNotifications: boolean;
	mcpServers: McpServer[];
	tools: string[];
	skillPlugins: string[];
	permissionAllow: string[];
	disallowedTools: string[];
	codexDisabledFeatures: string[];
	bridgeConfigSignature: string;
};

// pi baseline — matches what `coding-agent/src/core/system-prompt.ts` advertises
// as `Available tools:` (lowercase pi names map 1:1 to capitalized Claude Code
// tool names). Keeping these aligned is the whole point of the tool-surface
// constraint: the agent's stated tools and actual tools are identical.
const DEFAULT_CLAUDE_TOOLS: readonly string[] = ["Read", "Bash", "Edit", "Write"];

// Default permission allowlist mirrors the pi-baseline tool surface plus
// `mcp__*` so anything reaching us via the bridge MCP servers is auto-allowed.
// claude-agent-acp resolves `permissionMode` from the user's filesystem
// `~/.claude/settings.json`'s `permissions.defaultMode` (we cannot override
// that via `_meta`); combined with this explicit allow list, even a `default`
// or `auto` mode lets these tools through without prompts.
const DEFAULT_CLAUDE_PERMISSION_ALLOW: readonly string[] = ["Read(*)", "Bash(*)", "Edit(*)", "Write(*)", "mcp__*"];

// SDK 0.2.119 advertises a set of deferred tools via a system-reminder
// block ("The following deferred tools are now available via ToolSearch").
// `Options.tools` only filters the immediate function list — the deferred
// advertisement is a separate surface that slips through. Pi advertises a
// fixed 4–5 tool baseline in its system prompt, so the deferred set creates
// the same declared-vs-actual mismatch the explicit `tools` field was meant
// to prevent.
//
// We therefore disallow the full deferred set by default. claude-agent-acp
// already prunes one entry (`AskUserQuestion`) via its own disallowedTools
// list (acp-agent.ts:1719) — we re-include it for explicitness; the
// downstream spread (acp-agent.ts:1768) merges idempotently. Pi's own
// equivalents already cover every capability disallowed here:
//
//   Cron*               → /schedule skill
//   WebFetch/WebSearch  → brave-search MCP, summarize / medium-extractor
//   EnterPlanMode/...   → pi's plan model (separate)
//   EnterWorktree/...   → operator's git
//   Monitor/PushNotif…  → pi's tmux/session mechanisms
//   NotebookEdit        → covered by Edit
//   Task*/RemoteTrigger → entwurf + control-socket bridge
//
// When the SDK adds a new deferred tool, this list must follow.
const DEFAULT_CLAUDE_DISALLOWED_TOOLS: readonly string[] = [
	"AskUserQuestion",
	"CronCreate",
	"CronDelete",
	"CronList",
	"EnterPlanMode",
	"EnterWorktree",
	"ExitPlanMode",
	"ExitWorktree",
	"Monitor",
	"NotebookEdit",
	"PushNotification",
	"RemoteTrigger",
	"TaskCreate",
	"TaskGet",
	"TaskList",
	"TaskOutput",
	"TaskStop",
	"TaskUpdate",
	"WebFetch",
	"WebSearch",
];

// pi-shell-acp is an ACP BRIDGE provider, not a general-purpose OpenAI/Anthropic
// provider. It should NOT expose the full pi-ai model registry. Users who pick
// `pi-shell-acp/<model>` are choosing a specific bridge path (Claude Code ACP
// or codex-acp), so the surface is intentionally curated:
//
// - Claude backend: the two current frontier sonnet/opus we actually test against.
// - Codex backend: only the "agentic coding" gpt-5.x line in the openai-codex
//   source, which is what codex-acp spawns — NOT the openai source, whose
//   context/cost values reflect the Chat Completions API, not codex.
//
// Adding a model here means we commit to checking it across both Axis 1
// (protocol smoke) and Axis 2 (agent interview). Do not extend casually.
const SUPPORTED_ANTHROPIC_MODEL_IDS: readonly string[] = ["claude-sonnet-4-6", "claude-opus-4-7"] as const;
const SUPPORTED_CODEX_MODEL_IDS: readonly string[] = ["gpt-5.2", "gpt-5.4", "gpt-5.4-mini", "gpt-5.5"] as const;

const SUPPORTED_ANTHROPIC_SET = new Set(SUPPORTED_ANTHROPIC_MODEL_IDS);
const SUPPORTED_CODEX_SET = new Set(SUPPORTED_CODEX_MODEL_IDS);

// Codex metadata must come from `openai-codex` (not `openai`). The two sources
// diverge: `openai/gpt-5.5` declares 1,050,000 context (Chat Completions tier),
// while the `openai-codex` line declares the capacity codex-acp actually
// delivers (272,000 across the gpt-5.x line as of pi-ai 0.70.2). Reading from
// `openai` causes pi-shell-acp to advertise context it cannot serve — a
// concrete bug that showed up as "pi-shell-acp/gpt-5.5 ctx=1.1M" in
// --list-models.
const ANTHROPIC_MODELS_ALL = getModels("anthropic");
const CODEX_MODELS_ALL = getModels("openai-codex");

const ANTHROPIC_MODEL_IDS = new Set(ANTHROPIC_MODELS_ALL.map((m) => m.id));
const CODEX_MODEL_IDS = new Set(CODEX_MODELS_ALL.map((m) => m.id));

// Anthropic's registry reports 1_000_000 for Claude 4.6+ models, but our
// public pi-shell-acp surface deliberately distinguishes Sonnet vs Opus:
// - sonnet-4-6 stays at 200K by default
// - opus-4-6 / opus-4-7 surface at 1M by default
// Operators can still override the Claude cap globally via
// PI_SHELL_ACP_CLAUDE_CONTEXT when they need to pin a different value.
const CLAUDE_CONTEXT_DEFAULT = 1_000_000;
const CLAUDE_SONNET_DEFAULT = 200_000;
function resolveClaudeContextCap(): number | null {
	const raw = process.env.PI_SHELL_ACP_CLAUDE_CONTEXT?.trim();
	if (!raw) return null;
	const parsed = Number.parseInt(raw, 10);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}
const CLAUDE_CONTEXT_OVERRIDE = resolveClaudeContextCap();
function resolveClaudeModelContextWindow(model: { id: string; contextWindow: number }): number {
	if (CLAUDE_CONTEXT_OVERRIDE) return Math.min(model.contextWindow, CLAUDE_CONTEXT_OVERRIDE);
	const defaultCap = model.id === "claude-sonnet-4-6" ? CLAUDE_SONNET_DEFAULT : CLAUDE_CONTEXT_DEFAULT;
	return Math.min(model.contextWindow, defaultCap);
}

type AnthropicRegistryModel = (typeof ANTHROPIC_MODELS_ALL)[number];
type CodexRegistryModel = (typeof CODEX_MODELS_ALL)[number];

function requireRegistryModel<T extends AnthropicRegistryModel | CodexRegistryModel>(models: T[], id: string): T {
	const model = models.find((m) => m.id === id);
	if (!model) throw new Error(`Required base model is missing from pi-ai registry: ${id}`);
	return model;
}

function curatedAnthropicModels(): AnthropicRegistryModel[] {
	const models = ANTHROPIC_MODELS_ALL.filter((m) => SUPPORTED_ANTHROPIC_SET.has(m.id));
	if (!models.some((m) => m.id === "claude-opus-4-7")) {
		const base = requireRegistryModel(ANTHROPIC_MODELS_ALL, "claude-opus-4-6");
		models.push({
			...base,
			id: "claude-opus-4-7",
			name: "Claude Opus 4.7",
			contextWindow: 1_000_000,
		});
	}
	return models;
}

function curatedCodexModels(): CodexRegistryModel[] {
	const models = CODEX_MODELS_ALL.filter((m) => SUPPORTED_CODEX_SET.has(m.id));
	if (!models.some((m) => m.id === "gpt-5.5")) {
		const base = requireRegistryModel(CODEX_MODELS_ALL, "gpt-5.4");
		models.push({
			...base,
			id: "gpt-5.5",
			name: "GPT-5.5",
			contextWindow: 272_000,
		});
	}
	return models;
}

const CURATED_ANTHROPIC_MODELS = curatedAnthropicModels();
const CURATED_CODEX_MODELS = curatedCodexModels();

const MODELS = Array.from(
	new Map(
		[...CURATED_ANTHROPIC_MODELS, ...CURATED_CODEX_MODELS].map((model) => [
			model.id,
			{
				id: model.id,
				name: model.name,
				reasoning: model.reasoning,
				input: model.input,
				cost: model.cost,
				contextWindow: SUPPORTED_ANTHROPIC_SET.has(model.id)
					? resolveClaudeModelContextWindow(model)
					: model.contextWindow,
				maxTokens: model.maxTokens,
			},
		]),
	).values(),
);

function createEmptyUsage() {
	return {
		input: 0,
		output: 0,
		cacheRead: 0,
		cacheWrite: 0,
		totalTokens: 0,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
	};
}

function createOutputMessage(model: Model<any>): AssistantMessage {
	return {
		role: "assistant",
		content: [],
		api: model.api,
		provider: model.provider,
		model: model.id,
		usage: createEmptyUsage(),
		stopReason: "stop",
		timestamp: Date.now(),
	};
}

function resolveSessionKey(options: SimpleStreamOptions | undefined, cwd: string): string {
	const sessionId = (options as { sessionId?: string } | undefined)?.sessionId;
	return sessionId ? `pi:${sessionId}` : `cwd:${cwd}`;
}

function messageContentSignature(content: any): string {
	if (typeof content === "string") return `text:${content}`;
	if (!Array.isArray(content)) return "";
	return content
		.map((block) => {
			if (!block || typeof block !== "object") return "";
			switch (block.type) {
				case "text":
					return `text:${String(block.text ?? "")}`;
				case "image":
					return `image:${String(block.mimeType ?? block.source?.mimeType ?? block.source?.mediaType ?? "")}:${String(block.uri ?? block.source?.url ?? "")}`;
				case "thinking":
					return `thinking:${String(block.thinking ?? "")}`;
				case "toolCall":
					return `tool:${String(block.name ?? "")}:${JSON.stringify(block.arguments ?? {})}`;
				default:
					return `${String(block.type ?? "unknown")}:${JSON.stringify(block)}`;
			}
		})
		.join("|");
}

function getContextMessageSignatures(context: Context): string[] {
	return context.messages.map((message: any) => `${message.role}:${messageContentSignature(message.content)}`);
}

function settingsConfigError(filePath: string, message: string): Error {
	return new Error(`${filePath}: invalid piShellAcpProvider settings: ${message}`);
}

function assertOptionalBoolean(settings: Record<string, unknown>, key: string, filePath: string): boolean | undefined {
	const value = settings[key];
	if (value === undefined) return undefined;
	if (typeof value !== "boolean") throw settingsConfigError(filePath, `${key} must be a boolean`);
	return value;
}

function readSettingsFile(filePath: string): ProviderSettings {
	if (!existsSync(filePath)) return {};

	const raw = readFileSync(filePath, "utf-8");
	let parsed: unknown;
	try {
		parsed = JSON.parse(raw);
	} catch (error) {
		throw settingsConfigError(filePath, `malformed JSON (${error instanceof Error ? error.message : String(error)})`);
	}

	if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
		throw settingsConfigError(filePath, "settings file root must be an object");
	}

	const root = parsed as Record<string, unknown>;
	const settingsBlock = root["piShellAcpProvider"];
	if (settingsBlock === undefined) return {};
	if (!settingsBlock || typeof settingsBlock !== "object" || Array.isArray(settingsBlock)) {
		throw settingsConfigError(filePath, "piShellAcpProvider must be an object");
	}

	const settings = settingsBlock as Record<string, unknown>;
	const backend = settings["backend"];
	if (backend !== undefined && backend !== "claude" && backend !== "codex") {
		throw settingsConfigError(filePath, "backend must be one of: claude, codex");
	}

	const appendSystemPrompt = assertOptionalBoolean(settings, "appendSystemPrompt", filePath);
	const strictMcpConfig = assertOptionalBoolean(settings, "strictMcpConfig", filePath);
	const showToolNotifications = assertOptionalBoolean(settings, "showToolNotifications", filePath);

	const settingSourcesRaw = settings["settingSources"];
	let settingSources: ClaudeSettingSource[] | undefined;
	if (settingSourcesRaw !== undefined) {
		if (!Array.isArray(settingSourcesRaw)) {
			throw settingsConfigError(filePath, "settingSources must be an array");
		}
		if (
			!settingSourcesRaw.every(
				(value) => typeof value === "string" && (value === "user" || value === "project" || value === "local"),
			)
		) {
			throw settingsConfigError(filePath, "settingSources entries must be one of: user, project, local");
		}
		settingSources = settingSourcesRaw as ClaudeSettingSource[];
	}

	const mcpServersRaw = settings["mcpServers"];
	let mcpServers: McpServerInputMap | undefined;
	if (mcpServersRaw !== undefined) {
		if (!mcpServersRaw || typeof mcpServersRaw !== "object" || Array.isArray(mcpServersRaw)) {
			throw settingsConfigError(filePath, "mcpServers must be an object");
		}
		mcpServers = mcpServersRaw as McpServerInputMap;
	}

	const tools = parseStringArray(settings, "tools", filePath);
	const skillPlugins = parseStringArray(settings, "skillPlugins", filePath);
	const permissionAllow = parseStringArray(settings, "permissionAllow", filePath);
	const disallowedTools = parseStringArray(settings, "disallowedTools", filePath);
	const codexDisabledFeatures = parseStringArray(settings, "codexDisabledFeatures", filePath);

	return {
		backend: backend as AcpBackend | undefined,
		appendSystemPrompt,
		settingSources,
		strictMcpConfig,
		showToolNotifications,
		mcpServers,
		tools,
		skillPlugins,
		permissionAllow,
		disallowedTools,
		codexDisabledFeatures,
	};
}

function parseStringArray(settings: Record<string, unknown>, key: string, filePath: string): string[] | undefined {
	const value = settings[key];
	if (value === undefined) return undefined;
	if (!Array.isArray(value) || !value.every((entry) => typeof entry === "string")) {
		throw settingsConfigError(filePath, `${key} must be an array of strings`);
	}
	return value as string[];
}

// Once-per-process flag so the warning fires on first bootstrap but does not
// repeat on every prompt or model switch.
let codexFeatureGatingWarningEmitted = false;

// Detect the explicit-empty-array case (`"codexDisabledFeatures": []`) and
// warn the operator. The semantics differ from "absent" in a way that has
// already caused one regression downstream (agent-config 0.2.1-era workaround
// that survived the 0.2.2 nullish-guard fix and silently flipped the codex
// tool surface from fail-closed to fail-open). Absent → DEFAULT applies →
// 5 features disabled. Explicit `[]` → operator opt-out → all gating off,
// codex native multi_agent / apps / image_generation / tool_suggest /
// tool_search become callable. The warning lets operators who set `[]` by
// accident see the divergence at session start instead of discovering it
// turns later via a tool-availability surprise.
function warnIfCodexFeatureGatingDisabled(rawValue: readonly string[] | undefined): void {
	if (codexFeatureGatingWarningEmitted) return;
	if (rawValue === undefined) return;
	if (rawValue.length !== 0) return;
	codexFeatureGatingWarningEmitted = true;
	console.error(
		`[pi-shell-acp:warn] codexDisabledFeatures=[] in settings.json explicitly opts out of bridge feature gating; codex native multi_agent (spawn_agent et al.), apps (mcp__codex_apps__*), image_generation, tool_suggest, and tool_search are enabled. To restore the fail-closed default (${DEFAULT_CODEX_DISABLED_FEATURES.join(", ")}), remove the codexDisabledFeatures key. To gate a subset, list only the keys you want disabled.`,
	);
}

function inferBackendFromModel(model: Model<any>): AcpBackend {
	// Curated-first: the allowlist determines routing deterministically.
	if (SUPPORTED_CODEX_SET.has(model.id)) return "codex";
	if (SUPPORTED_ANTHROPIC_SET.has(model.id)) return "claude";
	// Fallback: if an ID outside the allowlist somehow reaches here (e.g. a
	// non-curated model was passed via explicit settings), consult the broader
	// pi-ai registry. This is a safety net, not the primary path.
	if (CODEX_MODEL_IDS.has(model.id)) return "codex";
	if (ANTHROPIC_MODEL_IDS.has(model.id)) return "claude";
	return model.id.startsWith("gpt-") || model.id.startsWith("o") || model.id.startsWith("codex") ? "codex" : "claude";
}

function loadProviderSettings(cwd: string, model: Model<any>): ResolvedProviderSettings {
	const globalSettings = readSettingsFile(GLOBAL_SETTINGS_PATH);
	const projectSettings = readSettingsFile(join(cwd, ".pi", "settings.json"));
	// Project overrides global, but only for keys the project actually sets —
	// readSettingsFile returns undefined for missing keys and JS spread treats
	// undefined as an override, which would silently nuke global values.
	const projectDefined = Object.fromEntries(
		Object.entries(projectSettings).filter(([, v]) => v !== undefined),
	) as ProviderSettings;
	const merged = { ...globalSettings, ...projectDefined };
	const backend = merged.backend ?? inferBackendFromModel(model);
	const backendSource = merged.backend ? "explicit" : "inferred";
	const appendSystemPrompt = merged.appendSystemPrompt ?? false;
	// settingSources defaults to []  (SDK isolation) — pi-shell-acp does not
	// inherit the user's filesystem Claude Code settings (MCP, hooks, env,
	// plugins, skills). Skills are delivered explicitly via skillPlugins; MCP
	// via mcpServers. Operators who want native filesystem inheritance can
	// opt in by setting `settingSources: ["user"]` (or "project"/"local").
	const settingSources = merged.settingSources ?? [];
	// strictMcpConfig defaults to true — only the MCP servers we provide via
	// `mcpServers` reach the backend. The user's `~/.mcp.json`, project
	// `.mcp.json`, and `~/.claude/settings.json` MCP entries are ignored.
	const strictMcpConfig = merged.strictMcpConfig ?? true;
	const showToolNotifications = merged.showToolNotifications ?? false;
	// Tool surface defaults to the pi baseline so the system prompt's
	// "Available tools:" line and the SDK's actual tools align (Read, Bash,
	// Edit, Write). MCP tools (mcp__*) are exposed independently via
	// mcpServers and are auto-allowed by the default permissionAllow.
	const skillPlugins = merged.skillPlugins ?? [];
	const baseTools = merged.tools ?? [...DEFAULT_CLAUDE_TOOLS];
	const baseAllow = merged.permissionAllow ?? [...DEFAULT_CLAUDE_PERMISSION_ALLOW];
	// When skillPlugins is non-empty, ensure the SDK's "Skill" tool is in the
	// surface. The SDK's skill-listing emitter (SN1 in claude-agent-sdk) is
	// gated on `tools.some(name === "Skill")`: without it, the listing returns
	// empty and skills never reach the system prompt — even though the plugin
	// loaded all skills/<name>/SKILL.md into memory. Verified against
	// claude-agent-sdk 0.2.114 and 0.2.119; the gate is identical in both, so
	// this is independent of the dep bump in 32a3dee. We also auto-allow
	// `Skill(*)` so the listing surface is not silently denied at the
	// permission layer.
	const tools = skillPlugins.length > 0 && !baseTools.includes("Skill") ? [...baseTools, "Skill"] : baseTools;
	const permissionAllow =
		skillPlugins.length > 0 && !baseAllow.includes("Skill(*)") ? [...baseAllow, "Skill(*)"] : baseAllow;
	const disallowedTools = merged.disallowedTools ?? [...DEFAULT_CLAUDE_DISALLOWED_TOOLS];
	// Distinguish absent (apply default fail-closed gating) from explicit `[]`
	// (operator opts fully out of bridge feature gating). The `??` collapses
	// both to a value, so we read the pre-merge field directly to detect the
	// explicit-empty case and warn — see warnIfCodexFeatureGatingDisabled().
	const codexDisabledFeatures = merged.codexDisabledFeatures ?? [...DEFAULT_CODEX_DISABLED_FEATURES];
	warnIfCodexFeatureGatingDisabled(merged.codexDisabledFeatures);
	const mergedMcpServersRaw: McpServerInputMap = {
		...(globalSettings.mcpServers ?? {}),
		...(projectSettings.mcpServers ?? {}),
	};
	const { servers: mcpServers, hash: mcpServersHash } = normalizeMcpServers(mergedMcpServersRaw);
	return {
		backend,
		backendSource,
		appendSystemPrompt,
		settingSources,
		strictMcpConfig,
		showToolNotifications,
		mcpServers,
		tools,
		skillPlugins,
		permissionAllow,
		disallowedTools,
		codexDisabledFeatures,
		bridgeConfigSignature: JSON.stringify({
			backend,
			appendSystemPrompt,
			settingSources,
			strictMcpConfig,
			mcpServersHash,
			tools,
			skillPlugins,
			permissionAllow,
			disallowedTools,
			codexDisabledFeatures,
		}),
	};
}

function extractPromptBlocks(
	context: Context,
): Array<{ type: "text"; text: string } | { type: "image"; data?: string; mimeType?: string; uri?: string }> {
	// Find the first user message after the last assistant message.
	// pi injects hook messages (e.g., SessionStart "device=..., time_kst=...") as additional
	// user messages AFTER the real prompt. Using reverse().find() would pick the hook message
	// instead of the actual prompt. By taking the first user message in the trailing group,
	// we reliably get the real prompt in both single-turn (-p) and multi-turn modes.
	let lastAssistantIdx = -1;
	for (let i = context.messages.length - 1; i >= 0; i--) {
		if (context.messages[i].role === "assistant") {
			lastAssistantIdx = i;
			break;
		}
	}
	const latestUserMessage = context.messages
		.slice(lastAssistantIdx + 1)
		.find((message) => message.role === "user") as any;
	if (!latestUserMessage) {
		return [{ type: "text", text: "" }];
	}

	const blocks: Array<
		{ type: "text"; text: string } | { type: "image"; data?: string; mimeType?: string; uri?: string }
	> = [];
	for (const block of latestUserMessage.content ?? []) {
		if (block?.type === "text") {
			blocks.push({ type: "text", text: String(block.text ?? "") });
			continue;
		}
		if (block?.type === "image") {
			const source = block.source ?? {};
			if (source.type === "base64") {
				blocks.push({
					type: "image",
					data: source.data,
					mimeType: source.mediaType ?? source.mimeType,
				});
			} else if (source.type === "url") {
				blocks.push({
					type: "image",
					uri: source.url,
				});
			}
		}
	}

	if (blocks.length === 0) {
		blocks.push({ type: "text", text: "" });
	}
	return blocks;
}

// pi-shell-acp follows the same context-meter convention as peer ACP clients
// (zed, obsidian-agent-client, openclaw-acpx): display the backend's
// `usage_update.used / size` directly. Both supported backends emit per-turn
// occupancy — claude-agent-acp via `input + output + cache_read +
// cache_creation` of the last assistant result, codex-acp via
// `tokens_in_context_window()`. event-mapper.ts records that value into
// `output.usage.totalTokens` while streaming; this function only fills the
// per-component fields from `PromptResponse.usage` so cost accounting and
// pi's BackendUsage stats line up.
//
// Two meter modes are surfaced in the diagnostic so audits can tell which
// number the footer is showing:
//   - `meter=acpUsageUpdate source=backend` — `usage_update` arrived during
//     streaming and the backend's per-turn occupancy was used.
//   - `meter=componentSum source=promptResponse` — no `usage_update` arrived
//     (some backends skip emitting on tool-only turns); the footer falls
//     back to summing PromptResponse components so it still has a value.
//
// IMPORTANT — semantic difference vs native pi:
// In pi-shell-acp the footer percentage follows the ACP backend's reported
// occupancy, not pi's visible-transcript estimate. The two values can differ
// because the backend counts its own prompt/cache/tool/session state on top
// of the visible transcript. A small pi conversation can map to a large ACP
// footer; that is a backend-overflow risk signal, not a meter bug.
function applyPromptUsage(
	model: Model<any>,
	output: AssistantMessage,
	promptResponse: any,
	backend: AcpBackend,
	acpUsageSeen: boolean,
	acpUsageSize: number | undefined,
): void {
	const usage = promptResponse?.usage;
	const hasUsage = usage && typeof usage === "object";

	const rawInput = hasUsage ? Number(usage.inputTokens ?? 0) : 0;
	const rawOutput = hasUsage ? Number(usage.outputTokens ?? 0) : 0;
	const rawCacheRead = hasUsage ? Number(usage.cachedReadTokens ?? 0) : 0;
	const rawCacheWrite = hasUsage ? Number(usage.cachedWriteTokens ?? 0) : 0;

	output.usage.input = rawInput;
	output.usage.output = rawOutput;
	output.usage.cacheRead = rawCacheRead;
	output.usage.cacheWrite = rawCacheWrite;

	// Pick meter mode by whether usage_update arrived, NOT by totalTokens > 0.
	// `used = 0` is a legitimate backend value (codex-acp clamps with
	// `.max(0)`, fresh-session edges can report zero) so a numeric check would
	// silently misclassify legitimate "occupancy is zero" reports as fallback.
	let meter: "acpUsageUpdate" | "componentSum";
	let source: "backend" | "promptResponse";
	if (acpUsageSeen) {
		meter = "acpUsageUpdate";
		source = "backend";
	} else {
		output.usage.totalTokens = rawInput + rawOutput + rawCacheRead + rawCacheWrite;
		meter = "componentSum";
		source = "promptResponse";
	}

	calculateCost(model, output.usage);

	const used = output.usage.totalTokens;
	const size = acpUsageSize ?? model.contextWindow;
	console.error(
		`[pi-shell-acp:usage] meter=${meter} source=${source} backend=${backend} used=${used} size=${size} ` +
			`raw: input=${rawInput} output=${rawOutput} cacheRead=${rawCacheRead} cacheWrite=${rawCacheWrite}`,
	);
}

function mapPromptStopReason(stopReason: string | undefined): AssistantMessage["stopReason"] {
	switch (stopReason) {
		case "max_tokens":
			return "length";
		case "cancelled":
			return "aborted";
		default:
			return "stop";
	}
}

function streamShellAcp(
	model: Model<any>,
	context: Context,
	options?: SimpleStreamOptions,
): AssistantMessageEventStream {
	const stream = createAssistantMessageEventStream();

	(async () => {
		const output = createOutputMessage(model);
		const cwd = (options as { cwd?: string } | undefined)?.cwd ?? process.cwd();
		const sessionKey = resolveSessionKey(options, cwd);
		const providerSettings = loadProviderSettings(cwd, model);
		let bridgeSession: Awaited<ReturnType<typeof ensureBridgeSession>> | undefined;

		const streamState: AcpPiStreamState = {
			stream,
			output,
			showToolNotifications: providerSettings.showToolNotifications,
		};

		// Start the pi stream before ACP bootstrap. Resume/load can take noticeable
		// time, and delaying `start` until after ensureBridgeSession() makes the UI
		// look stuck even though work is already in progress.
		stream.push({ type: "start", partial: output });

		try {
			const baseSystemPrompt = providerSettings.appendSystemPrompt ? context.systemPrompt : undefined;

			// Engraving — self-recognition prompt from prompts/engraving.md,
			// rendered once here and delivered per-backend at the highest
			// stable identity-carrier surface each backend exposes:
			//
			// - Claude: sent as `_meta.systemPrompt = <string>` so
			//   claude-agent-acp performs full preset replacement against the
			//   string-form Options.systemPrompt union (sdk.d.ts:1695). The
			//   claude_code preset disappears from the system prompt; the
			//   engraving sits directly above the SDK's hard-wired minimum
			//   identity prefix.
			// - Codex: sent as `-c developer_instructions="<...>"` at
			//   codex-acp child spawn time, landing inside the codex
			//   `developer` role between the binary's `permissions` /
			//   `apps` / `skills` instruction blocks. codex-acp does not
			//   honor `_meta.systemPrompt`, so this is the highest stable
			//   carrier the codex stack exposes.
			//
			// The rendered engraving is stable across turns (pure function of
			// template × backend × mcpServerNames). On Claude it travels in
			// `systemPromptAppend`; on Codex it travels in
			// `codexDeveloperInstructions`. Both fields are part of session
			// compatibility checks — changing either forces a fresh bridge
			// session so the new engraving is actually delivered to the
			// model.
			const engraving = loadEngraving({
				backend: providerSettings.backend,
				mcpServerNames: providerSettings.mcpServers.map((s) => s.name),
			});
			const claudeEngraving = providerSettings.backend === "claude" ? engraving : null;
			const codexEngraving = providerSettings.backend === "codex" ? engraving : null;

			const systemPromptParts = [baseSystemPrompt, claudeEngraving ?? undefined].filter(
				(part): part is string => typeof part === "string" && part.length > 0,
			);
			const mergedSystemPromptAppend = systemPromptParts.length > 0 ? systemPromptParts.join("\n\n") : undefined;
			const codexDeveloperInstructions = codexEngraving && codexEngraving.length > 0 ? codexEngraving : undefined;

			bridgeSession = await ensureBridgeSession({
				sessionKey,
				cwd,
				backend: providerSettings.backend,
				modelId: model.id,
				systemPromptAppend: mergedSystemPromptAppend,
				codexDeveloperInstructions,
				settingSources: providerSettings.settingSources,
				strictMcpConfig: providerSettings.strictMcpConfig,
				mcpServers: providerSettings.mcpServers,
				tools: providerSettings.tools,
				skillPlugins: providerSettings.skillPlugins,
				permissionAllow: providerSettings.permissionAllow,
				disallowedTools: providerSettings.disallowedTools,
				codexDisabledFeatures: providerSettings.codexDisabledFeatures,
				bridgeConfigSignature: providerSettings.bridgeConfigSignature,
				contextMessageSignatures: getContextMessageSignatures(context),
			});
			logBridgeDiagnostic("session", {
				...describeBridgeSession(bridgeSession),
				backendSource: providerSettings.backendSource,
			});

			setActivePromptHandler(bridgeSession, async (event) => {
				if (event.type === "session_notification" && event.notification?.sessionId !== bridgeSession?.acpSessionId) {
					return;
				}
				applyBridgePromptEvent(streamState, event as any);
			});

			const promptBlocks = extractPromptBlocks(context);

			// ESC / abort handling.
			//
			// We race the actual prompt against the abort signal. The abort
			// branch resolves to null after dispatching cancel to the backend,
			// so the stream closes immediately on ESC instead of blocking on a
			// backend that may take seconds (or never) to acknowledge cancel.
			//
			// The sendPrompt promise can still resolve or reject after we've
			// already taken the abort branch — we attach a no-op `.catch` so
			// late rejections don't surface as unhandledRejection, and the
			// finally block clears setActivePromptHandler so any late
			// session_notification updates are dropped on the floor.
			const sendPromise = sendPrompt(bridgeSession, promptBlocks);
			sendPromise.catch(() => {
				// late rejection after abort; intentionally swallowed
			});

			const abortPromise = new Promise<null>((resolve) => {
				const signal = options?.signal;
				if (!signal) return; // never resolves — race falls back to sendPromise
				const dispatchCancel = () => {
					if (bridgeSession) {
						void cancelActivePrompt(bridgeSession).catch(() => {
							// cancel best-effort; backend may not implement it
						});
					}
					resolve(null);
				};
				if (signal.aborted) {
					dispatchCancel();
					return;
				}
				signal.addEventListener("abort", dispatchCancel, { once: true });
			});

			const promptResponse = await Promise.race([sendPromise, abortPromise]);

			if (promptResponse === null) {
				output.stopReason = "aborted";
				output.errorMessage = "Operation aborted";
				finalizeAcpStreamState(streamState);
				stream.push({ type: "error", reason: "aborted", error: output });
				stream.end();
				return;
			}

			applyPromptUsage(
				model,
				output,
				promptResponse,
				providerSettings.backend,
				streamState.acpUsageSeen === true,
				streamState.acpUsageSize,
			);
			output.stopReason = mapPromptStopReason(promptResponse?.stopReason);
			finalizeAcpStreamState(streamState);

			if (options?.signal?.aborted || output.stopReason === "aborted") {
				output.errorMessage = "Operation aborted";
				stream.push({ type: "error", reason: "aborted", error: output });
				stream.end();
				return;
			}

			stream.push({
				type: "done",
				reason: output.stopReason === "length" ? "length" : "stop",
				message: output,
			});
			stream.end();
		} catch (error) {
			output.stopReason = options?.signal?.aborted ? "aborted" : "error";
			output.errorMessage = getBridgeErrorDetails(error, bridgeSession);
			finalizeAcpStreamState(streamState);
			stream.push({
				type: "error",
				reason: output.stopReason === "aborted" ? "aborted" : "error",
				error: output,
			});
			stream.end();
			if (output.stopReason === "error" && bridgeSession) {
				try {
					await closeBridgeSession(bridgeSession.key, {
						closeRemote: true,
						invalidatePersisted: false,
					});
				} catch {
					// best-effort cleanup; already reported via stream error
				}
			}
		} finally {
			// abort listener uses { once: true } and self-removes after firing,
			// so no manual removeEventListener is needed here. setActivePromptHandler
			// is cleared below so any session_notification arriving after we
			// returned via the abort path is dropped instead of pushed into a
			// closed stream.
			if (bridgeSession) {
				setActivePromptHandler(bridgeSession, undefined);
			}
		}
	})();

	return stream;
}

export default function (pi: ExtensionAPI) {
	if (isRegisteredOnRuntime(pi)) {
		return;
	}
	markRegisteredOnRuntime(pi);

	const on = pi.on as unknown as (
		event: string,
		handler: (event: Record<string, unknown>, ctx: { sessionManager?: { getSessionId?: () => string } }) => void,
	) => void;

	on("session_shutdown", async (_event, ctx) => {
		const sessionId = ctx?.sessionManager?.getSessionId?.();
		if (!sessionId) return;
		await cleanupBridgeSessionProcess(`pi:${sessionId}`);
	});

	// Block all compaction at the host (pi) level.
	//
	// pi runs four compaction paths today, and three of them are silent:
	//   1. silent overflow recovery (`isContextOverflow` Case 2 — input + cacheRead > window)
	//   2. threshold compaction (`shouldCompact(contextTokens, contextWindow, settings)`)
	//   3. explicit error overflow recovery
	//   4. manual `/compact` invoked by the operator
	//
	// All four go through `session_before_compact`, so returning `{ cancel: true }`
	// here covers them as a group. That removes the need for the operator to
	// remember to set `compaction.enabled=false` in their pi settings — this
	// repo is the one with the policy ("non-compaction is the autonomous-
	// operation invariant"), so the gate belongs here, not in agent-config.
	//
	// Manual `/compact` users get a clear "Compaction cancelled" surface from
	// agent-session.js, so the intent stays observable. If an operator really
	// wants pi-side compaction back (e.g. a long-running maintenance session),
	// `PI_SHELL_ACP_ALLOW_COMPACTION=1` opts out of this guard at process level.
	on("session_before_compact", () => {
		const allow = process.env.PI_SHELL_ACP_ALLOW_COMPACTION?.trim().toLowerCase();
		if (allow === "1" || allow === "true" || allow === "yes") {
			return;
		}
		console.error(
			"[pi-shell-acp:compaction] blocked at session_before_compact — pi-shell-acp keeps pi as the single context-management authority. Set PI_SHELL_ACP_ALLOW_COMPACTION=1 to opt out.",
		);
		return { cancel: true };
	});

	pi.registerProvider(PROVIDER_ID, {
		baseUrl: "pi-shell-acp",
		apiKey: "ANTHROPIC_API_KEY",
		api: "pi-shell-acp",
		models: MODELS,
		streamSimple: streamShellAcp,
	});
}
