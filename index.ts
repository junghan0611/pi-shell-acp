import { existsSync, readdirSync, readFileSync } from "node:fs";
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
};

type ResolvedProviderSettings = {
	backend: AcpBackend;
	backendSource: "explicit" | "inferred";
	appendSystemPrompt: boolean;
	settingSources: ClaudeSettingSource[];
	strictMcpConfig: boolean;
	showToolNotifications: boolean;
	mcpServers: McpServer[];
	bridgeConfigSignature: string;
};

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
// while `openai-codex/gpt-5.5` declares 400,000 (the capacity codex-acp
// actually delivers). Reading from `openai` causes pi-shell-acp to advertise
// context it cannot serve — a concrete bug that showed up as
// "pi-shell-acp/gpt-5.5 ctx=1.1M" in --list-models.
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
			contextWindow: 400_000,
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

function estimateTextTokens(text: string): number {
	return Math.ceil(text.length / 4);
}

function estimatePiMessageTokens(message: any): number {
	let chars = 0;
	switch (message?.role) {
		case "user": {
			const content = message.content;
			if (typeof content === "string") return estimateTextTokens(content);
			if (Array.isArray(content)) {
				for (const block of content) {
					if (block?.type === "text") chars += String(block.text ?? "").length;
					if (block?.type === "image") chars += 4800;
				}
			}
			return Math.ceil(chars / 4);
		}
		case "assistant": {
			for (const block of message.content ?? []) {
				if (block?.type === "text") chars += String(block.text ?? "").length;
				else if (block?.type === "thinking") chars += String(block.thinking ?? "").length;
				else if (block?.type === "toolCall") {
					chars += String(block.name ?? "").length + JSON.stringify(block.arguments ?? {}).length;
				}
			}
			return Math.ceil(chars / 4);
		}
		case "toolResult": {
			const content = message.content;
			if (typeof content === "string") return estimateTextTokens(content);
			if (Array.isArray(content)) {
				for (const block of content) {
					if (block?.type === "text") chars += String(block.text ?? "").length;
					if (block?.type === "image") chars += 4800;
				}
			}
			return Math.ceil(chars / 4);
		}
		default:
			return 0;
	}
}

function piSessionDirForCwd(cwd: string): string {
	const slug = cwd.replace(/^\/+/, "").replace(/\/+$/, "").replace(/\//g, "-");
	return join(homedir(), ".pi", "agent", "sessions", `--${slug}--`);
}

function findPiSessionFile(cwd: string, sessionKey: string): string | undefined {
	if (!sessionKey.startsWith("pi:")) return undefined;
	const sessionId = sessionKey.slice("pi:".length);
	if (!sessionId) return undefined;
	const dir = piSessionDirForCwd(cwd);
	if (!existsSync(dir)) return undefined;
	for (const name of readdirSync(dir)) {
		if (name.endsWith(".jsonl") && name.includes(sessionId)) return join(dir, name);
	}
	return undefined;
}

function estimatePiSessionFileTokens(cwd: string, sessionKey: string): number | undefined {
	const file = findPiSessionFile(cwd, sessionKey);
	if (!file) return undefined;
	let tokens = 0;
	for (const line of readFileSync(file, "utf-8").split("\n")) {
		if (!line.trim()) continue;
		try {
			const entry = JSON.parse(line) as any;
			if (entry?.type === "message") tokens += estimatePiMessageTokens(entry.message);
		} catch {
			// Ignore malformed/truncated lines; session persistence is append-only.
		}
	}
	return tokens;
}

// VisibleTranscript: chars/4 estimate over the pi session JSONL plus the
// current assistant output. This is one *component* of the eventual
// PiOccupancy meter, not the SSOT itself — it omits backend system prompt,
// tool definitions, project context, and skill payloads, which on real
// resume sessions can be the majority of the LLM context. PR-B will add a
// calibrated prefixOverhead and switch the footer to PiOccupancy.
function estimateVisibleTranscriptTokens(
	context: Context,
	output: AssistantMessage,
	cwd: string,
	sessionKey: string,
): number {
	const sessionFileTokens = estimatePiSessionFileTokens(cwd, sessionKey);
	if (sessionFileTokens !== undefined) return sessionFileTokens + estimatePiMessageTokens(output);

	let tokens = 0;
	for (const message of context.messages as any[]) {
		tokens += estimatePiMessageTokens(message);
	}
	tokens += estimatePiMessageTokens(output);
	return tokens;
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

	return {
		backend: backend as AcpBackend | undefined,
		appendSystemPrompt,
		settingSources,
		strictMcpConfig,
		showToolNotifications,
		mcpServers,
	};
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
	const settingSources = merged.settingSources ?? (appendSystemPrompt ? [] : ["user"]);
	const strictMcpConfig = merged.strictMcpConfig ?? false;
	const showToolNotifications = merged.showToolNotifications ?? false;
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
		bridgeConfigSignature: JSON.stringify({
			backend,
			appendSystemPrompt,
			settingSources,
			strictMcpConfig,
			mcpServersHash,
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

function applyPromptUsage(
	model: Model<any>,
	context: Context,
	output: AssistantMessage,
	promptResponse: any,
	cwd: string,
	sessionKey: string,
): void {
	const usage = promptResponse?.usage;
	if (!usage || typeof usage !== "object") return;

	// Keep raw backend usage components for cost/stat accounting (BackendUsage),
	// but do not use the backend's aggregate totalTokens as pi's context meter.
	//
	// ACP backends such as Claude Code may perform multiple internal LLM calls
	// inside one pi turn (plan → tool → final answer). Their PromptResponse usage
	// is an *execution aggregate* across those internal calls, not "the size of
	// the pi session context", so it overstates occupancy on tool turns.
	//
	// Current state: footer % is driven by VisibleTranscript only (mode below).
	// This is honest but incomplete — it omits backend system prompt, tool
	// definitions, and project context, so resume sessions can read very low
	// (e.g. 0.4% on a session with 2.3M cacheRead). PR-B replaces this with
	// PiOccupancy = prefixOverhead + visibleTranscript + outputCorrection,
	// where prefixOverhead is calibrated once per session signature.
	// See llmlog 20260426T082246, level-1 heading "합의된 해결안".
	const rawInput = Number(usage.inputTokens ?? 0);
	const rawOutput = Number(usage.outputTokens ?? 0);
	const rawCacheRead = Number(usage.cachedReadTokens ?? 0);
	const rawCacheWrite = Number(usage.cachedWriteTokens ?? 0);
	const rawTotal = Number(usage.totalTokens ?? rawInput + rawOutput + rawCacheRead + rawCacheWrite);
	const visibleTranscriptTokens = estimateVisibleTranscriptTokens(context, output, cwd, sessionKey);

	output.usage.input = rawInput;
	output.usage.output = rawOutput;
	output.usage.cacheRead = rawCacheRead;
	output.usage.cacheWrite = rawCacheWrite;
	output.usage.totalTokens = visibleTranscriptTokens;
	calculateCost(model, output.usage);

	// Diagnostic with explicit mode so "why is the footer at X%" is traceable
	// without spelunking pi internals or backend logs. mode flips to
	// "piOccupancy" in PR-B once calibrated prefixOverhead is in place.
	console.error(
		`[pi-shell-acp:usage] mode=visibleTranscriptOnly ` +
			`tokens=${visibleTranscriptTokens} ` +
			`backendRaw: input=${rawInput} output=${rawOutput} ` +
			`cacheRead=${rawCacheRead} cacheWrite=${rawCacheWrite} rawTotal=${rawTotal}`,
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
			// rendered once here and delivered per-backend:
			// - Claude: concatenated into systemPromptAppend alongside
			//   baseSystemPrompt, routed through pi's _meta.systemPrompt.append path.
			// - Codex: passed as bootstrapPromptAugment; the Codex backend
			//   adapter turns it into a ContentBlock::Text prepended to the
			//   first prompt of a new session, since codex-acp has no
			//   equivalent _meta extension we can rely on.
			// The rendered engraving is stable across turns (pure function of
			// template × backend × mcpServerNames), so it never drives session
			// invalidation by itself.
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
			const bootstrapPromptAugment = codexEngraving && codexEngraving.length > 0 ? codexEngraving : undefined;

			bridgeSession = await ensureBridgeSession({
				sessionKey,
				cwd,
				backend: providerSettings.backend,
				modelId: model.id,
				systemPromptAppend: mergedSystemPromptAppend,
				bootstrapPromptAugment,
				settingSources: providerSettings.settingSources,
				strictMcpConfig: providerSettings.strictMcpConfig,
				mcpServers: providerSettings.mcpServers,
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

			applyPromptUsage(model, context, output, promptResponse, cwd, sessionKey);
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
