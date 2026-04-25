import { calculateCost, createAssistantMessageEventStream, getModels, type AssistantMessage, type AssistantMessageEventStream, type Context, type Model, type SimpleStreamOptions } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { applyBridgePromptEvent, finalizeAcpStreamState, type AcpPiStreamState } from "./event-mapper.js";
import { cancelActivePrompt, cleanupBridgeSessionProcess, closeBridgeSession, describeBridgeSession, ensureBridgeSession, getBridgeErrorDetails, normalizeMcpServers, sendPrompt, setActivePromptHandler, type AcpBackend, type ClaudeSettingSource, type McpServerInputMap } from "./acp-bridge.js";
import { detectCompactionContext, renderCompactionSystemPromptAppend } from "./compaction-context.js";
import { loadEngraving } from "./engraving.js";
import type { McpServer } from "@agentclientprotocol/sdk";

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
	mcpServers?: McpServerInputMap;
};

type ResolvedProviderSettings = {
	backend: AcpBackend;
	backendSource: "explicit" | "inferred";
	appendSystemPrompt: boolean;
	settingSources: ClaudeSettingSource[];
	strictMcpConfig: boolean;
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
const SUPPORTED_ANTHROPIC_MODEL_IDS: readonly string[] = [
	"claude-sonnet-4-6",
	"claude-opus-4-7",
] as const;
const SUPPORTED_CODEX_MODEL_IDS: readonly string[] = [
	"gpt-5.2",
	"gpt-5.4",
	"gpt-5.4-mini",
	"gpt-5.5",
] as const;

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

function readSettingsFile(filePath: string): ProviderSettings {
	if (!existsSync(filePath)) return {};
	try {
		const raw = readFileSync(filePath, "utf-8");
		const parsed = JSON.parse(raw) as Record<string, unknown>;
		const settingsBlock =
			(parsed["piShellAcpProvider"] as Record<string, unknown> | undefined);
		if (!settingsBlock || typeof settingsBlock !== "object") return {};
		const backend = settingsBlock["backend"];
		const resolvedBackend = backend === "claude" || backend === "codex" ? backend : undefined;
		const appendSystemPrompt =
			typeof settingsBlock["appendSystemPrompt"] === "boolean"
				? (settingsBlock["appendSystemPrompt"] as boolean)
				: undefined;
		const settingSourcesRaw = settingsBlock["settingSources"];
		const settingSources =
			Array.isArray(settingSourcesRaw) &&
			settingSourcesRaw.every(
				(value) => typeof value === "string" && (value === "user" || value === "project" || value === "local"),
			)
				? (settingSourcesRaw as ClaudeSettingSource[])
				: undefined;
		const strictMcpConfig =
			typeof settingsBlock["strictMcpConfig"] === "boolean"
				? (settingsBlock["strictMcpConfig"] as boolean)
				: undefined;
		const mcpServersRaw = settingsBlock["mcpServers"];
		const mcpServers =
			mcpServersRaw && typeof mcpServersRaw === "object" && !Array.isArray(mcpServersRaw)
				? (mcpServersRaw as McpServerInputMap)
				: undefined;
		return {
			backend: resolvedBackend,
			appendSystemPrompt,
			settingSources,
			strictMcpConfig,
			mcpServers,
		};
	} catch {
		return {};
	}
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
	return model.id.startsWith("gpt-") || model.id.startsWith("o") || model.id.startsWith("codex")
		? "codex"
		: "claude";
}

function loadProviderSettings(cwd: string, model: Model<any>): ResolvedProviderSettings {
	const globalSettings = readSettingsFile(GLOBAL_SETTINGS_PATH);
	const projectSettings = readSettingsFile(join(cwd, ".pi", "settings.json"));
	const merged = { ...globalSettings, ...projectSettings };
	const backend = merged.backend ?? inferBackendFromModel(model);
	const backendSource = merged.backend ? "explicit" : "inferred";
	const appendSystemPrompt = merged.appendSystemPrompt ?? false;
	const settingSources = merged.settingSources ?? (appendSystemPrompt ? [] : ["user"]);
	const strictMcpConfig = merged.strictMcpConfig ?? false;
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

function extractPromptBlocks(context: Context): Array<{ type: "text"; text: string } | { type: "image"; data?: string; mimeType?: string; uri?: string }> {
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
	const latestUserMessage = context.messages.slice(lastAssistantIdx + 1).find((message) => message.role === "user") as any;
	if (!latestUserMessage) {
		return [{ type: "text", text: "" }];
	}

	const blocks: Array<{ type: "text"; text: string } | { type: "image"; data?: string; mimeType?: string; uri?: string }> = [];
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

function applyPromptUsage(model: Model<any>, output: AssistantMessage, promptResponse: any): void {
	const usage = promptResponse?.usage;
	if (!usage || typeof usage !== "object") return;
	output.usage.input = Number(usage.inputTokens ?? 0);
	output.usage.output = Number(usage.outputTokens ?? 0);
	output.usage.cacheRead = Number(usage.cachedReadTokens ?? 0);
	output.usage.cacheWrite = Number(usage.cachedWriteTokens ?? 0);
	// Context-metric alignment with pi native behaviour.
	//
	// pi-coding-agent's calculateContextTokens(usage) reads usage.totalTokens
	// first and falls back to input+output+cacheRead+cacheWrite only when
	// totalTokens is 0. That metric drives BOTH the TUI footer context-%
	// display AND compaction timing decisions.
	//
	// The ACP backends we route (Claude Code, Codex) use prompt caching very
	// aggressively on their side, so cacheRead often dominates totals (e.g.
	// 769K cacheRead inside a 789K turn). On pi native the same metric shape
	// exists but cacheRead is usually ~0 because pi-ai doesn't inject
	// cache_control the way Claude Code does. The observable mismatch on ACP
	// routes: the footer looks near-full even when the live conversation is
	// small, and compaction fires early.
	//
	// We keep cacheRead / cacheWrite populated (billing cost in calculateCost
	// below reads them), but set totalTokens to input+output only — the same
	// shape a pi native provider produces when prompt caching is not active.
	// Result: pi's context metric reflects live-conversation growth, compaction
	// timing stays honest, and cost accounting stays accurate.
	output.usage.totalTokens = output.usage.input + output.usage.output;
	calculateCost(model, output.usage);
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

function streamShellAcp(model: Model<any>, context: Context, options?: SimpleStreamOptions): AssistantMessageEventStream {
	const stream = createAssistantMessageEventStream();

	(async () => {
		const output = createOutputMessage(model);
		const cwd = (options as { cwd?: string } | undefined)?.cwd ?? process.cwd();
		const sessionKey = resolveSessionKey(options, cwd);
		const providerSettings = loadProviderSettings(cwd, model);
		let bridgeSession: Awaited<ReturnType<typeof ensureBridgeSession>> | undefined;
		let aborted = false;

		const streamState: AcpPiStreamState = {
			stream,
			output,
		};

		const onAbort = () => {
			aborted = true;
			if (bridgeSession) {
				void cancelActivePrompt(bridgeSession).catch(() => {
					// ignore
				});
			}
		};

		if (options?.signal) {
			if (options.signal.aborted) onAbort();
			else options.signal.addEventListener("abort", onAbort, { once: true });
		}

		try {
			// Post-compaction handoff — only meaningful for Claude backend (the
			// Codex adapter doesn't forward systemPromptAppend today). When pi
			// compacts, its next call to us carries a synthetic user message that
			// holds the summary; without this handoff the new Claude session
			// bootstraps cold because extractPromptBlocks only sends the latest
			// user turn. pi session stays canonical — we just project pi's
			// compacted view into the new Claude session once via system prompt,
			// and rely on identical systemPromptAppend across subsequent turns to
			// keep the reuse branch alive.
			const compaction = providerSettings.backend === "claude" ? detectCompactionContext(context) : null;
			const baseSystemPrompt = providerSettings.appendSystemPrompt ? context.systemPrompt : undefined;
			const compactionAppend = compaction ? renderCompactionSystemPromptAppend(compaction) : undefined;

			// Engraving — self-recognition prompt from prompts/engraving.md,
			// rendered once here and delivered per-backend:
			// - Claude: concatenated into systemPromptAppend alongside
			//   baseSystemPrompt + compactionAppend, routed through pi's
			//   _meta.systemPrompt.append path.
			// - Codex: passed as bootstrapPromptAugment; the Codex backend
			//   adapter turns it into a ContentBlock::Text prepended to the
			//   first prompt of a new session, since codex-acp has no
			//   equivalent _meta extension we can rely on.
			// The rendered output is stable across turns (pure function of
			// template × backend × mcpServerNames), so bridgeConfigSignature
			// + systemPromptAppend + bootstrapPromptAugment hashes all match
			// on reuse and session continuity is preserved.
			const engraving = loadEngraving({
				backend: providerSettings.backend,
				mcpServerNames: providerSettings.mcpServers.map((s) => s.name),
			});
			const claudeEngraving = providerSettings.backend === "claude" ? engraving : null;
			const codexEngraving = providerSettings.backend === "codex" ? engraving : null;

			const systemPromptParts = [baseSystemPrompt, claudeEngraving ?? undefined, compactionAppend].filter(
				(part): part is string => typeof part === "string" && part.length > 0,
			);
			const mergedSystemPromptAppend =
				systemPromptParts.length > 0 ? systemPromptParts.join("\n\n") : undefined;
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

			stream.push({ type: "start", partial: output });

			const promptBlocks = extractPromptBlocks(context);
			const promptResponse = await sendPrompt(bridgeSession, promptBlocks);
			applyPromptUsage(model, output, promptResponse);
			output.stopReason = mapPromptStopReason(promptResponse?.stopReason);
			finalizeAcpStreamState(streamState);

			if (aborted || options?.signal?.aborted || output.stopReason === "aborted") {
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
			output.stopReason = aborted || options?.signal?.aborted ? "aborted" : "error";
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
			if (options?.signal) {
				options.signal.removeEventListener("abort", onAbort);
			}
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

	pi.registerProvider(PROVIDER_ID, {
		baseUrl: "pi-shell-acp",
		apiKey: "ANTHROPIC_API_KEY",
		api: "pi-shell-acp",
		models: MODELS,
		streamSimple: streamShellAcp,
	});
}
