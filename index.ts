import { calculateCost, createAssistantMessageEventStream, getModels, type AssistantMessage, type AssistantMessageEventStream, type Context, type Model, type SimpleStreamOptions } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { applyAcpSessionUpdate, finalizeAcpStreamState, type AcpPiStreamState } from "./event-mapper.js";
import { cancelActivePrompt, closeBridgeSession, ensureBridgeSession, getBridgeErrorDetails, sendPrompt, setActivePromptHandler } from "./acp-bridge.js";

const PROVIDER_ID = "claude-agent-sdk";
const REGISTERED_SYMBOL = Symbol.for("claude-agent-sdk-pi:registered");

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

function extractPromptBlocks(context: Context): Array<{ type: "text"; text: string } | { type: "image"; data?: string; mimeType?: string; uri?: string }> {
	const latestUserMessage = [...context.messages].reverse().find((message) => message.role === "user") as any;
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
				systemPromptAppend: context.systemPrompt,
			});

			setActivePromptHandler(bridgeSession, async (notification) => {
				if (notification?.sessionId !== bridgeSession?.acpSessionId) return;
				applyAcpSessionUpdate(streamState, notification.update as any);
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
		await closeBridgeSession(`pi:${sessionId}`);
	});

	pi.registerProvider(PROVIDER_ID, {
		baseUrl: "claude-agent-sdk",
		apiKey: "ANTHROPIC_API_KEY",
		api: "claude-agent-sdk",
		models: MODELS,
		streamSimple: streamClaudeAcp,
	});
}
