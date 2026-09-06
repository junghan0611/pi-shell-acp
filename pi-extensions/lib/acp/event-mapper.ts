// ACP plugin — ACP session_notification → pi event stream mapper (S2c).
//
// Translates the ACP backend's streaming notifications into pi's
// AssistantMessageEvent protocol (text/thinking blocks + tool/permission
// notices + usage), maintaining a running `partial: AssistantMessage`.
//
// Single-dialect collapse (NEXT §스코프 + oracle F): the 0.11.0 event-mapper
// reconciled three backend dialects (Claude rawOutput=array / Codex
// CallToolResult / Gemini content[]) plus an entwurf_v2 sent-box custom promotion.
// This lane collapsed that to ONE dialect (rawOutput=array) and dropped the
// entwurf/gemini/codex special-casing.
//
// This module is COMMON layer, not a claude module: the cortex landing reused THIS
// FILE with no adapter branch and no edit, and the CP2 LIVE turn ran through it.
// (That is a fact about this mapper only — the landing did touch other common files,
// e.g. backend.ts's overlay call site.) The collapse is therefore a standing bet,
// not a proof: a future backend whose session_notification dialect differs from
// rawOutput=array reopens this file rather than forking it per backend.
//
// CRITICAL boundary (GPT S2c Q3): an ACP `tool_call` / `tool_call_update` is
// rendered as an INFORMATIONAL TEXT NOTICE, never a structured pi `toolcall_*`
// event. The ACP child already executes its own tools (Claude Code side); a
// structured pi ToolCall would signal pi's agent loop to RE-EXECUTE it. Tools
// surface honestly in the transcript as `[tool:*]` notices instead. Thinking
// (`agent_thought_chunk`) IS structured — pi never executes thinking.

import type { AssistantMessage, AssistantMessageEventStream } from "@earendil-works/pi-ai";

const NOTICE_TITLE_MAX = 80;
const NOTICE_SUMMARY_MAX = 160;

/** Identity fields for the running assistant message. */
export interface AcpStreamIdentity {
	api: string;
	provider: string;
	model: string;
}

type ObservedToolState = {
	title: string;
	status?: string;
};

export type AcpPiStreamState = {
	stream: AssistantMessageEventStream;
	output: AssistantMessage;
	openTextIndex?: number;
	openThinkingIndex?: number;
	/** When false, tool/permission notices are suppressed (kept terse for smokes). */
	showToolNotifications?: boolean;
	observedTools?: Map<string, ObservedToolState>;
	/**
	 * RAW, UNINTERPRETED observations from this turn's `usage_update` notifications
	 * — carried beside the pi message, never folded into it here.
	 *
	 * The mapper is COMMON layer and deliberately assigns no meaning to either
	 * number: what `cost.amount` is CUMULATIVE OVER, and whether that even holds
	 * for a non-claude backend, is a per-backend measurement. backend.ts seals them
	 * only for a backend whose adapter declares `sealsTurnAccounting` (#93).
	 *
	 * Last write wins, never a sum: both are latest session-level observations, and
	 * one turn can legitimately see several (claude emits one per `result` message,
	 * including a sub-agent's own — read at claude-agent-acp 0.75.1
	 * `dist/acp-agent.js:3467-3482`), each carrying that result's current values.
	 */
	observedSessionCostUsd?: number;
	observedContextOccupancyTokens?: number;
};

/** A zeroed pi Usage block. */
function zeroUsage(): AssistantMessage["usage"] {
	return {
		input: 0,
		output: 0,
		cacheRead: 0,
		cacheWrite: 0,
		totalTokens: 0,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
	};
}

/**
 * Build a fresh stream state with an empty running AssistantMessage. The caller
 * (streamSimple) pushes the `start` event, drives notifications through
 * applyAcpSessionUpdate, then finalize + done.
 */
export function createAcpStreamState(
	stream: AssistantMessageEventStream,
	identity: AcpStreamIdentity,
	opts?: { showToolNotifications?: boolean; timestamp?: number },
): AcpPiStreamState {
	const output: AssistantMessage = {
		role: "assistant",
		content: [],
		api: identity.api,
		provider: identity.provider,
		model: identity.model,
		usage: zeroUsage(),
		// Seed, not a verdict. pi 0.83 added "pending" for exactly this: a partial
		// streaming message has not observed a terminal reason yet, and every pi
		// provider seeds it here and treats a stream that ENDS still-pending as an
		// error rather than a successful stop. Seeding "stop" instead would
		// pre-claim success for the whole time the turn is in flight.
		stopReason: "pending",
		timestamp: opts?.timestamp ?? Date.now(),
	};
	return {
		stream,
		output,
		showToolNotifications: opts?.showToolNotifications ?? true,
	};
}

function getObservedTools(state: AcpPiStreamState): Map<string, ObservedToolState> {
	if (!state.observedTools) state.observedTools = new Map();
	return state.observedTools;
}

function closeThinkingBlock(state: AcpPiStreamState): void {
	if (state.openThinkingIndex == null) return;
	const index = state.openThinkingIndex;
	const block = state.output.content[index] as { thinking?: string };
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
	const block = state.output.content[index] as { text?: string };
	state.stream.push({ type: "text_end", contentIndex: index, content: block?.text ?? "", partial: state.output });
	state.openTextIndex = undefined;
}

function ensureTextBlock(state: AcpPiStreamState): number {
	if (state.openTextIndex != null) return state.openTextIndex;
	closeThinkingBlock(state);
	const index = state.output.content.length;
	state.output.content.push({ type: "text", text: "" });
	state.openTextIndex = index;
	state.stream.push({ type: "text_start", contentIndex: index, partial: state.output });
	return index;
}

function ensureThinkingBlock(state: AcpPiStreamState): number {
	if (state.openThinkingIndex != null) return state.openThinkingIndex;
	closeTextBlock(state);
	const index = state.output.content.length;
	state.output.content.push({ type: "thinking", thinking: "", thinkingSignature: "" });
	state.openThinkingIndex = index;
	state.stream.push({ type: "thinking_start", contentIndex: index, partial: state.output });
	return index;
}

/**
 * Emit a standalone one-line notice as its own text block. Used for tool /
 * permission events — informational, NOT structured tool calls.
 */
function pushNotice(state: AcpPiStreamState, text: string): void {
	if (!state.showToolNotifications || !text.trim()) return;
	closeThinkingBlock(state);
	closeTextBlock(state);
	const index = state.output.content.length;
	state.output.content.push({ type: "text", text });
	state.stream.push({ type: "text_start", contentIndex: index, partial: state.output });
	state.stream.push({ type: "text_delta", contentIndex: index, delta: text, partial: state.output });
	state.stream.push({ type: "text_end", contentIndex: index, content: text, partial: state.output });
}

/**
 * Sanitize an inline fragment for the one-line `[tool:*]` / `[permission:*]`
 * notice surface: collapse whitespace, neutralize backtick fences (which would
 * otherwise swallow following lines in chat renderers), truncate with ellipsis.
 */
export function sanitizeNoticeFragment(text: string | null | undefined, max: number): string {
	if (!text) return "";
	const collapsed = text.replace(/\s+/g, " ").trim();
	const fenceSafe = collapsed.replace(/`{3,}/g, "[fence]").replace(/`/g, "'");
	if (fenceSafe.length <= max) return fenceSafe;
	return `${fenceSafe.slice(0, max - 1)}…`;
}

function firstTextItem(arr: unknown[]): string | undefined {
	for (const item of arr) {
		if (item && typeof item === "object" && (item as { type?: string }).type === "text") {
			const text = String((item as { text?: unknown }).text ?? "").trim();
			if (text) return text;
		}
		// ACP-normalized shape: { type:"content", content:{ type:"text", text } }
		if (item && typeof item === "object" && (item as { type?: string }).type === "content") {
			const inner = (item as { content?: { type?: string; text?: unknown } }).content;
			if (inner && typeof inner === "object" && inner.type === "text") {
				const text = String(inner.text ?? "").trim();
				if (text) return text;
			}
		}
	}
	return undefined;
}

/** Claude ACP rawOutput is an array of text items; tolerate a CallToolResult body too. */
function firstTextContent(value: unknown): string | undefined {
	if (Array.isArray(value)) {
		const text = firstTextItem(value);
		if (text) return text;
	}
	if (!value || typeof value !== "object") return undefined;
	const inner = (value as { content?: unknown }).content;
	if (Array.isArray(inner)) {
		const text = firstTextItem(inner);
		if (text) return text;
	}
	return undefined;
}

/** MCP-level error flag on a CallToolResult-shaped rawOutput. */
function rawOutputHasError(rawOutput: unknown): boolean {
	if (!rawOutput || typeof rawOutput !== "object") return false;
	return (rawOutput as { isError?: unknown }).isError === true;
}

function titleForTool(update: Record<string, unknown>, previousTitle?: string): string {
	const meta = update?._meta as { claudeCode?: { toolName?: string } } | undefined;
	return String(update?.title ?? previousTitle ?? meta?.claudeCode?.toolName ?? update?.toolCallId ?? "Tool");
}

/**
 * Render an ACP tool_call / tool_call_update as a text notice (NEVER a
 * structured toolcall — the ACP child already executed it).
 */
function renderToolUpdate(state: AcpPiStreamState, update: Record<string, unknown>): void {
	const toolCallId = String(update?.toolCallId ?? "");
	if (!toolCallId) return;
	const observedTools = getObservedTools(state);
	const previous = observedTools.get(toolCallId);
	const title = titleForTool(update, previous?.title);
	const status = typeof update?.status === "string" ? (update.status as string) : previous?.status;
	const updateContent = Array.isArray(update?.content) ? (update.content as unknown[]) : undefined;

	if (update.sessionUpdate === "tool_call") {
		observedTools.set(toolCallId, { title, status });
		pushNotice(state, `\n[tool:start] ${sanitizeNoticeFragment(title, NOTICE_TITLE_MAX)}\n`);
		return;
	}

	// tool_call_update. There is deliberately no mid-flight `[tool:running]`
	// notice: it would have to be driven by the adapter's `_meta.terminal_output`,
	// and that meta is gated upstream on `clientCapabilities._meta.terminal_output
	// === true` while backend.ts initializes with `clientCapabilities: {}`. So the
	// branch could never fire for any backend we ship — it claimed a transcript
	// line the operator was never going to see. Declaring the terminal capability
	// is a separate axis, not a one-line re-enable: the adapter would then send
	// terminal widgets/metas this mapper cannot render honestly into a transcript.
	if (status && status !== previous?.status) {
		const summary = firstTextContent(update?.rawOutput) ?? firstTextContent(updateContent);
		const suffix = summary ? ` — ${sanitizeNoticeFragment(summary, NOTICE_SUMMARY_MAX)}` : "";
		if (status === "completed") {
			const label = rawOutputHasError(update?.rawOutput) ? "tool:failed" : "tool:done";
			pushNotice(state, `\n[${label}] ${sanitizeNoticeFragment(title, NOTICE_TITLE_MAX)}${suffix}\n`);
		} else if (status === "failed") {
			pushNotice(state, `\n[tool:failed] ${sanitizeNoticeFragment(title, NOTICE_TITLE_MAX)}${suffix}\n`);
		} else if (status === "cancelled") {
			pushNotice(state, `\n[tool:cancelled] ${sanitizeNoticeFragment(title, NOTICE_TITLE_MAX)}${suffix}\n`);
		}
	}

	observedTools.set(toolCallId, { title, status });
}

/** Push a permission-decision notice (informational text, not a tool call). */
export function pushPermissionNotice(state: AcpPiStreamState, title: string, decision: string): void {
	pushNotice(state, `\n[permission:${decision}] ${sanitizeNoticeFragment(title, NOTICE_TITLE_MAX)}\n`);
}

/**
 * The textSignature marker stamped on lifecycle progress notices (S2f). It is
 * what lets the transcript flatten (context.ts) and the reuse-compat signature
 * (session-store.ts) EXCLUDE these blocks: a lifecycle notice is display-only —
 * it must never replay into an ACP prompt nor perturb a reuse signature, whether
 * present or absent. Without the marker the "output-side only" claim is L0 hope.
 */
export const LIFECYCLE_NOTICE_SIGNATURE = "entwurf:lifecycle-notice-v1";

/**
 * Push a one-line ACP turn-lifecycle progress notice (`[acp: …]`) as its own
 * text block, stamped with LIFECYCLE_NOTICE_SIGNATURE. Two ways it differs from
 * tool/permission notices:
 *   1. It IGNORES `showToolNotifications`. Turn progress is ALWAYS visible — a
 *      silent bootstrap (overlay → spawn → init → newSession → setModel → first
 *      token) reads as a hang. Only the verbose tool stream is suppressible.
 *   2. The marker keeps it display-only — out of the transcript replay and the
 *      reuse-compat signature (the two consumers filter on the signature).
 */
export function pushAcpLifecycleNotice(state: AcpPiStreamState, text: string): void {
	const line = `\n[acp: ${sanitizeNoticeFragment(text, NOTICE_TITLE_MAX)}]\n`;
	closeThinkingBlock(state);
	closeTextBlock(state);
	const index = state.output.content.length;
	state.output.content.push({ type: "text", text: line, textSignature: LIFECYCLE_NOTICE_SIGNATURE });
	state.stream.push({ type: "text_start", contentIndex: index, partial: state.output });
	state.stream.push({ type: "text_delta", contentIndex: index, delta: line, partial: state.output });
	state.stream.push({ type: "text_end", contentIndex: index, content: line, partial: state.output });
}

/**
 * Apply one ACP `session_notification` update to the stream state. Unknown
 * update kinds are ignored (forward-compatible).
 */
export function applyAcpSessionUpdate(
	state: AcpPiStreamState,
	update: Record<string, unknown> | null | undefined,
): void {
	if (!update || typeof update !== "object") return;

	switch (update.sessionUpdate) {
		case "agent_message_chunk": {
			const content = update.content as { type?: string; text?: unknown } | undefined;
			if (content?.type !== "text") return;
			const delta = String(content.text ?? "");
			if (!delta) return;
			const index = ensureTextBlock(state);
			(state.output.content[index] as { text: string }).text += delta;
			state.stream.push({ type: "text_delta", contentIndex: index, delta, partial: state.output });
			break;
		}
		case "agent_thought_chunk": {
			const content = update.content as { type?: string; text?: unknown } | undefined;
			if (content?.type !== "text") return;
			const delta = String(content.text ?? "");
			if (!delta) return;
			const index = ensureThinkingBlock(state);
			(state.output.content[index] as { thinking: string }).thinking += delta;
			state.stream.push({ type: "thinking_delta", contentIndex: index, delta, partial: state.output });
			break;
		}
		case "tool_call":
		case "tool_call_update": {
			renderToolUpdate(state, update);
			break;
		}
		case "usage_update": {
			// `used` is OCCUPANCY-shaped — the backend's post-turn context size, not
			// the prompt response's turn aggregate. Claude sends `lastAssistantTotalUsage`
			// as `used` (read at claude-agent-acp 0.75.1
			// `dist/acp-agent.js:3867-3878`), after constructing that scalar from the
			// latest assistant snapshot (`:3853-3866`). pi reads `usage.totalTokens` as
			// exactly that occupancy (`calculateContextTokens(usage) = usage.totalTokens
			// || input + output + cacheRead + cacheWrite`, read at pi-coding-agent
			// `dist/core/compaction/compaction.js:86-88`). The assignment below is the
			// raw observation; backend.ts seals the measured occupancy and relays the
			// turn aggregate separately on `usage.acp`, never onto pi's four fields.
			if (typeof update.used === "number") {
				state.output.usage.totalTokens = update.used;
				state.observedContextOccupancyTokens = update.used;
			}
			// `cost.amount` is a running SESSION total on the claude backend, so
			// assigning it to a TURN field is wrong wherever an adapter has measured
			// that (#93: pi sums per-message cost, which inflated a long session
			// 10-18x). It stays here for a backend whose adapter has NOT measured its
			// semantics — for those, this coarse assignment is the pre-#93 behaviour
			// and changing it would be an unmeasured claim. backend.ts OVERWRITES
			// this field authoritatively (from the baseline diff) for every turn of a
			// backend that HAS sealsTurnAccounting, so the cumulative can never reach
			// an operator's dashboard as a turn cost on that path.
			const cost = update.cost as { amount?: unknown } | undefined;
			if (typeof cost?.amount === "number") {
				state.output.usage.cost.total = cost.amount;
				state.observedSessionCostUsd = cost.amount;
			}
			break;
		}
		default:
			break;
	}
}

/** Close any open text/thinking block. Call before pushing the terminal done. */
export function finalizeAcpStreamState(state: AcpPiStreamState): void {
	closeThinkingBlock(state);
	closeTextBlock(state);
}
