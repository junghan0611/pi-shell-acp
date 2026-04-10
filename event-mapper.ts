import type { AssistantMessage, AssistantMessageEventStream } from "@mariozechner/pi-ai";

export type AcpPiStreamState = {
	stream: AssistantMessageEventStream;
	output: AssistantMessage;
	openTextIndex?: number;
	openThinkingIndex?: number;
};

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

export function applyAcpSessionUpdate(state: AcpPiStreamState, update: any): void {
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
		case "usage_update": {
			if (typeof update.used === "number") {
				state.output.usage.totalTokens = update.used;
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

export function finalizeAcpStreamState(state: AcpPiStreamState): void {
	closeThinkingBlock(state);
	closeTextBlock(state);
}
