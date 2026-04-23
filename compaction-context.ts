import type { Context, Message } from "@mariozechner/pi-ai";

// Must stay in sync with pi-coding-agent's messages.ts. pi converts a
// CompactionEntry into a user message whose text starts with this exact prefix
// before the provider (us) sees it. Any drift here breaks detection silently,
// so we keep the literal tightly coupled with the upstream constant.
const COMPACTION_SUMMARY_PREFIX = `The conversation history before this point was compacted into the following summary:

<summary>
`;

const COMPACTION_SUMMARY_SUFFIX = `
</summary>`;

export interface CompactionContext {
	/** Raw summary text recovered from inside the <summary> block. */
	summary: string;
	/** Messages between the compaction summary and the latest user turn — the "kept recent" window from pi. */
	keptMessages: Message[];
	/** Absolute index in context.messages of the latest user message. -1 if no user turn is present after the summary. */
	latestUserIndex: number;
}

function extractFirstText(content: Message["content"]): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	for (const block of content) {
		if (block && typeof block === "object" && (block as any).type === "text") {
			return String((block as any).text ?? "");
		}
	}
	return "";
}

/**
 * Detect whether the first message in `context` carries pi's compaction summary.
 * Returns null if no compaction summary is present (normal path).
 *
 * pi's Agent runs convertToLlm() before calling the provider, which flattens the
 * CompactionSummaryMessage into a plain `role: "user"` message whose first text
 * block is wrapped by COMPACTION_SUMMARY_PREFIX/SUFFIX. That wrapping is the
 * only stable signal we get; detection is a textual prefix match on message[0].
 */
export function detectCompactionContext(context: Context): CompactionContext | null {
	const first = context.messages[0] as Message | undefined;
	if (!first || first.role !== "user") return null;
	const text = extractFirstText(first.content);
	if (!text.startsWith(COMPACTION_SUMMARY_PREFIX)) return null;

	const start = COMPACTION_SUMMARY_PREFIX.length;
	const end = text.endsWith(COMPACTION_SUMMARY_SUFFIX) ? text.length - COMPACTION_SUMMARY_SUFFIX.length : text.length;
	const summary = text.slice(start, end);

	// Mirror extractPromptBlocks' latest-user logic: find the last assistant,
	// then the first user message after it. When there is no assistant yet
	// (e.g. compaction happened very early, leaving [summary, new_user_turn]),
	// treat the summary at index 0 as the boundary — the real turn is the
	// first user message at index >= 1, never the summary itself.
	let boundaryIdx = -1;
	for (let i = context.messages.length - 1; i >= 0; i--) {
		if ((context.messages[i] as Message).role === "assistant") {
			boundaryIdx = i;
			break;
		}
	}
	if (boundaryIdx === -1) boundaryIdx = 0;
	let latestUserIdx = -1;
	for (let i = boundaryIdx + 1; i < context.messages.length; i++) {
		if ((context.messages[i] as Message).role === "user") {
			latestUserIdx = i;
			break;
		}
	}

	// Kept = everything between the summary (index 0) and the latest user turn.
	// If no latest user turn is detected (shouldn't happen in practice since pi
	// only invokes the provider when the user submits a turn), fall back to
	// everything after the summary.
	const keptEnd = latestUserIdx === -1 ? context.messages.length : latestUserIdx;
	const keptMessages = context.messages.slice(1, keptEnd) as Message[];

	return { summary, keptMessages, latestUserIndex: latestUserIdx };
}

function renderMessageAsText(m: Message): string {
	if (typeof m.content === "string") return m.content;
	if (!Array.isArray(m.content)) return "";
	const parts: string[] = [];
	for (const block of m.content) {
		if (block && typeof block === "object" && (block as any).type === "text") {
			parts.push(String((block as any).text ?? ""));
		}
		// thinking / image / toolCall blocks are dropped. On the pi-shell-acp
		// path the assistant content only holds text+thinking anyway (tool use
		// arrives as embedded [tool:*] notices inside the text block — see
		// event-mapper.ts), so this loses no structural data.
	}
	return parts.join("");
}

/**
 * Render pi's compaction summary + kept recent messages into a deterministic
 * systemPromptAppend string. The output must be stable across turns (same input
 * → identical output) so that isSessionCompatible's systemPromptAppend equality
 * check lets the Claude session reuse on turns 22, 23, ... after the post-
 * compaction turn 21 created it.
 */
export function renderCompactionSystemPromptAppend(comp: CompactionContext): string {
	const parts: string[] = [];
	parts.push("--- Earlier conversation summary (from pi-side compaction) ---");
	parts.push(comp.summary);
	if (comp.keptMessages.length > 0) {
		parts.push("");
		parts.push("--- Recent exchanges preserved verbatim ---");
		for (const m of comp.keptMessages) {
			const role = m.role === "user" ? "User" : m.role === "assistant" ? "Assistant" : m.role;
			const text = renderMessageAsText(m);
			if (text.length === 0) continue;
			parts.push(`${role}: ${text}`);
		}
	}
	parts.push("");
	parts.push("--- End of preserved context. Continue the conversation from here. ---");
	return parts.join("\n");
}

/** Exported so run.sh's check-compaction-handoff gate can assert the literal. */
export const COMPACTION_PREFIX_LITERAL = COMPACTION_SUMMARY_PREFIX;
export const COMPACTION_SUFFIX_LITERAL = COMPACTION_SUMMARY_SUFFIX;
