import { calculateCost, createAssistantMessageEventStream, getModels, type AssistantMessage, type AssistantMessageEventStream, type Context, type Model, type SimpleStreamOptions } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { applyBridgePromptEvent, finalizeAcpStreamState, type AcpPiStreamState } from "./event-mapper.js";
import { cancelActivePrompt, cleanupBridgeSessionProcess, ensureBridgeSession, getBridgeErrorDetails, normalizeMcpServers, sendPrompt, setActivePromptHandler, type ClaudeSettingSource, type McpServerInputMap } from "./acp-bridge.js";
import type { McpServer } from "@agentclientprotocol/sdk";

const PROVIDER_ID = "pi-shell-acp";
const REGISTERED_SYMBOL = Symbol.for("pi-shell-acp:registered");
const GLOBAL_SETTINGS_PATH = join(homedir(), ".pi", "agent", "settings.json");

type ProviderSettings = {
	appendSystemPrompt?: boolean;
	settingSources?: ClaudeSettingSource[];
	strictMcpConfig?: boolean;
	mcpServers?: McpServerInputMap;
};

type ResolvedProviderSettings = {
	appendSystemPrompt: boolean;
	settingSources: ClaudeSettingSource[];
	strictMcpConfig: boolean;
	mcpServers: McpServer[];
	bridgeConfigSignature: string;
};

const MODELS = getModels("anthropic").map((model) => ({
	id: model.id,
	name: model.name,
	reasoning: model.reasoning,
	input: model.input,
	cost: model.cost,
	contextWindow: model.contextWindow,
	maxTokens: model.maxTokens,
}));

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
			appendSystemPrompt,
			settingSources,
			strictMcpConfig,
			mcpServers,
		};
	} catch {
		return {};
	}
}

function loadProviderSettings(cwd: string): ResolvedProviderSettings {
	const globalSettings = readSettingsFile(GLOBAL_SETTINGS_PATH);
	const projectSettings = readSettingsFile(join(cwd, ".pi", "settings.json"));
	const merged = { ...globalSettings, ...projectSettings };
	const appendSystemPrompt = merged.appendSystemPrompt ?? false;
	const settingSources = merged.settingSources ?? (appendSystemPrompt ? [] : ["user"]);
	const strictMcpConfig = merged.strictMcpConfig ?? false;
	const mergedMcpServersRaw: McpServerInputMap = {
		...(globalSettings.mcpServers ?? {}),
		...(projectSettings.mcpServers ?? {}),
	};
	const { servers: mcpServers, signatureKey: mcpSignatureKey } = normalizeMcpServers(mergedMcpServersRaw);
	return {
		appendSystemPrompt,
		settingSources,
		strictMcpConfig,
		mcpServers,
		bridgeConfigSignature: JSON.stringify({
			appendSystemPrompt,
			settingSources,
			strictMcpConfig,
			mcpServers: mcpSignatureKey,
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
	output.usage.totalTokens = Number(
		usage.totalTokens ??
			output.usage.input + output.usage.output + output.usage.cacheRead + output.usage.cacheWrite,
	);
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

function streamClaudeAcp(model: Model<any>, context: Context, options?: SimpleStreamOptions): AssistantMessageEventStream {
	const stream = createAssistantMessageEventStream();

	(async () => {
		const output = createOutputMessage(model);
		const cwd = (options as { cwd?: string } | undefined)?.cwd ?? process.cwd();
		const sessionKey = resolveSessionKey(options, cwd);
		const providerSettings = loadProviderSettings(cwd);
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
			bridgeSession = await ensureBridgeSession({
				sessionKey,
				cwd,
				modelId: model.id,
				systemPromptAppend: providerSettings.appendSystemPrompt ? context.systemPrompt : undefined,
				settingSources: providerSettings.settingSources,
				strictMcpConfig: providerSettings.strictMcpConfig,
				mcpServers: providerSettings.mcpServers,
				bridgeConfigSignature: providerSettings.bridgeConfigSignature,
				contextMessageSignatures: getContextMessageSignatures(context),
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
	if ((globalThis as any)[REGISTERED_SYMBOL]) {
		return;
	}
	(globalThis as any)[REGISTERED_SYMBOL] = true;

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
		streamSimple: streamClaudeAcp,
	});
}
