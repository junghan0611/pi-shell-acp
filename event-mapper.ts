import type { AssistantMessage, AssistantMessageEventStream } from "@mariozechner/pi-ai";
import type { BridgePromptEvent } from "./acp-bridge.js";

type ObservedToolState = {
	title: string;
	status?: string;
	notifiedRunning?: boolean;
};

export type AcpPiStreamState = {
	stream: AssistantMessageEventStream;
	output: AssistantMessage;
	openTextIndex?: number;
	openThinkingIndex?: number;
	showToolNotifications?: boolean;
	observedTools?: Map<string, ObservedToolState>;
	// Last `usage_update.size` reported by the ACP backend on this turn.
	// claude-agent-acp adjusts its `contextWindowSize` based on the per-result
	// `modelUsage` block, so backends can shift the reported size mid-session
	// (e.g. when a per-model tier swap kicks in). We carry this through to the
	// diagnostic line so audits show the size the backend actually claimed,
	// not just the static `model.contextWindow`.
	acpUsageSize?: number;
	// True once any `usage_update` notification with a numeric `used` field
	// has arrived. We track this as a boolean rather than checking
	// `totalTokens > 0` because `used = 0` is a legitimate value — codex-acp
	// uses `tokens_in_context_window().max(0)` (explicitly allows 0), and
	// fresh-session / pre-first-call edges can also report 0. Treating 0 as
	// "no usage_update" would silently fall back to the componentSum path
	// when the backend was actually telling us "occupancy is zero."
	acpUsageSeen?: boolean;
};

function getObservedTools(state: AcpPiStreamState): Map<string, ObservedToolState> {
	if (!state.observedTools) {
		state.observedTools = new Map();
	}
	return state.observedTools;
}

function closeThinkingBlock(state: AcpPiStreamState): void {
	if (state.openThinkingIndex == null) return;
	const index = state.openThinkingIndex;
	const block = state.output.content[index] as any;
	state.stream.push({
		type: "thinking_end",
		contentIndex: index,
		content: block?.thinking ?? "",
		partial: state.output,
	});
	state.openThinkingIndex = undefined;
}

function closeTextBlock(state: AcpPiStreamState): void {
	if (state.openTextIndex == null) return;
	const index = state.openTextIndex;
	const block = state.output.content[index] as any;
	state.stream.push({
		type: "text_end",
		contentIndex: index,
		content: block?.text ?? "",
		partial: state.output,
	});
	state.openTextIndex = undefined;
}

function ensureTextBlock(state: AcpPiStreamState): number {
	if (state.openTextIndex != null) return state.openTextIndex;
	closeThinkingBlock(state);
	const index = state.output.content.length;
	state.output.content.push({ type: "text", text: "" } as any);
	state.openTextIndex = index;
	state.stream.push({ type: "text_start", contentIndex: index, partial: state.output });
	return index;
}

function ensureThinkingBlock(state: AcpPiStreamState): number {
	if (state.openThinkingIndex != null) return state.openThinkingIndex;
	closeTextBlock(state);
	const index = state.output.content.length;
	state.output.content.push({ type: "thinking", thinking: "", thinkingSignature: "" } as any);
	state.openThinkingIndex = index;
	state.stream.push({ type: "thinking_start", contentIndex: index, partial: state.output });
	return index;
}

function pushNotice(state: AcpPiStreamState, text: string): void {
	if (!state.showToolNotifications || !text.trim()) return;
	closeThinkingBlock(state);
	closeTextBlock(state);
	const index = state.output.content.length;
	state.output.content.push({ type: "text", text: text } as any);
	state.stream.push({ type: "text_start", contentIndex: index, partial: state.output });
	state.stream.push({ type: "text_delta", contentIndex: index, delta: text, partial: state.output });
	state.stream.push({ type: "text_end", contentIndex: index, content: text, partial: state.output });
}

function firstTextContent(value: unknown): string | undefined {
	if (!Array.isArray(value)) return undefined;
	for (const item of value) {
		if (item && typeof item === "object" && (item as any).type === "text") {
			const text = String((item as any).text ?? "").trim();
			if (text) return text;
		}
	}
	return undefined;
}

function titleForTool(update: any, previousTitle?: string, toolCallId?: string): string {
	return String(update?.title ?? previousTitle ?? update?._meta?.claudeCode?.toolName ?? toolCallId ?? "Tool");
}

function renderToolUpdate(state: AcpPiStreamState, update: any): void {
	const toolCallId = String(update?.toolCallId ?? "");
	if (!toolCallId) return;
	const observedTools = getObservedTools(state);
	const previous = observedTools.get(toolCallId);
	const title = titleForTool(update, previous?.title, toolCallId);
	const status = typeof update?.status === "string" ? update.status : previous?.status;
	const next: ObservedToolState = {
		title,
		status,
		notifiedRunning: previous?.notifiedRunning,
	};
	observedTools.set(toolCallId, next);

	if (update.sessionUpdate === "tool_call") {
		pushNotice(state, `\n[tool:start] ${title}\n`);
		return;
	}

	if (update?._meta?.terminal_output && !previous?.notifiedRunning) {
		next.notifiedRunning = true;
		observedTools.set(toolCallId, next);
		pushNotice(state, `\n[tool:running] ${title}\n`);
	}

	if (status && status !== previous?.status) {
		const summary = firstTextContent(update?.rawOutput);
		if (status === "completed") {
			pushNotice(state, `\n[tool:done] ${title}${summary ? ` — ${summary.slice(0, 160)}` : ""}\n`);
		} else if (status === "failed") {
			pushNotice(state, `\n[tool:failed] ${title}${summary ? ` — ${summary.slice(0, 160)}` : ""}\n`);
		} else if (status === "cancelled") {
			pushNotice(state, `\n[tool:cancelled] ${title}\n`);
		}
	}
}

function renderPermissionEvent(
	state: AcpPiStreamState,
	event: Extract<BridgePromptEvent, { type: "permission_request" }>,
): void {
	const title = String((event.request as any)?.toolCall?.title ?? "Tool");
	const outcome = (event.response as any)?.outcome;
	let decision = "cancelled";
	if (outcome?.outcome === "selected") {
		const optionId = String(outcome.optionId ?? "");
		decision = optionId.includes("allow") ? "approved" : optionId.includes("reject") ? "rejected" : "selected";
	}
	pushNotice(state, `\n[permission:${decision}] ${title}\n`);
}

function applyAcpSessionUpdate(state: AcpPiStreamState, update: any): void {
	if (!update || typeof update !== "object") return;

	switch (update.sessionUpdate) {
		case "agent_message_chunk": {
			if (update.content?.type !== "text") return;
			const delta = String(update.content.text ?? "");
			if (!delta) return;
			const index = ensureTextBlock(state);
			const block = state.output.content[index] as any;
			block.text += delta;
			state.stream.push({
				type: "text_delta",
				contentIndex: index,
				delta,
				partial: state.output,
			});
			break;
		}
		case "agent_thought_chunk": {
			if (update.content?.type !== "text") return;
			const delta = String(update.content.text ?? "");
			if (!delta) return;
			const index = ensureThinkingBlock(state);
			const block = state.output.content[index] as any;
			block.thinking += delta;
			state.stream.push({
				type: "thinking_delta",
				contentIndex: index,
				delta,
				partial: state.output,
			});
			break;
		}
		case "tool_call":
		case "tool_call_update": {
			renderToolUpdate(state, update);
			break;
		}
		case "usage_update": {
			if (typeof update.used === "number") {
				state.output.usage.totalTokens = update.used;
				state.acpUsageSeen = true;
			}
			if (typeof update.size === "number") {
				state.acpUsageSize = update.size;
			}
			if (typeof update.cost?.amount === "number") {
				state.output.usage.cost.total = update.cost.amount;
			}
			break;
		}
		default:
			break;
	}
}

export function applyBridgePromptEvent(state: AcpPiStreamState, event: BridgePromptEvent): void {
	if (event.type === "session_notification") {
		applyAcpSessionUpdate(state, event.notification.update as any);
		return;
	}
	if (event.type === "permission_request") {
		renderPermissionEvent(state, event);
	}
}

export function finalizeAcpStreamState(state: AcpPiStreamState): void {
	closeThinkingBlock(state);
	closeTextBlock(state);
}
