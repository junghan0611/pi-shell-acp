// ACP client adapter — the ONE place that touches the @agentclientprotocol/sdk
// 1.1 fluent surface (`client({ name }).connect(stream)`).
//
// The wire SDK deprecated the `new ClientSideConnection(toClient, stream)`
// constructor in favour of the fluent `client()` builder. The two have
// different shapes: the deprecated class implemented `Agent` directly (so
// `.initialize()`/`.newSession()`/`.prompt()` were methods on the returned
// object), while `client(...).connect(stream)` returns a persistent
// `ClientConnection` whose `.agent` is a `ClientContext` driven by
// `request(<method>, params)`.
//
// `connect()` (NOT `connectWith()`) is the right primitive here: the backend
// retains the connection on a BridgeSession and reuses it across turns
// (backend.ts), so the op-scoped close semantics of `connectWith` do not fit.
//
// This module owns the `AcpConnectionLike` seam so the backend and the live
// smokes both drive ONE adapter — the SDK method-name mapping lives here only,
// and the backend's orchestration + the gate fakes stay untouched.

import {
	type Usage as AcpWireUsage,
	AGENT_METHODS,
	CLIENT_METHODS,
	client,
	type Stream,
} from "@agentclientprotocol/sdk";
import type { AcpTextBlock } from "./context.js";

/**
 * What `session/prompt` answers with — entwurf's own narrow view of the SDK's
 * `PromptResponse`.
 *
 * `stopReason` stays `string | undefined` DELIBERATELY, not the SDK's closed
 * `StopReason` union: backend.ts's verdict mapping owes an honest answer for an
 * unknown or absent reason (it seals those as errors), and typing the field as
 * the closed union would make that branch look unreachable.
 *
 * `usage` reuses the SDK's own `Usage` type rather than a hand-copy, so a field
 * rename upstream is a typecheck failure here instead of a silent zero. It is
 * marked `@experimental` upstream and its per-field comments say "across all
 * turns/session" while the outer one says "for this turn" — that contradiction
 * is why NO common code interprets this shape — and #93 then measured that the
 * counts are a per-turn ROUND-TRIP AGGREGATE, which is not what any of pi's four
 * `Usage` fields mean. It is read in exactly ONE place, `sealTurnUsage`, which
 * relays it verbatim onto `usage.acp` (an accounting key, never a per-request
 * shape) and never onto those four. A field rename upstream fails the typecheck
 * here rather than silently zeroing the operator's cache-effect badge.
 */
/** One `_meta.quota.token_count` row (claude-agent-acp 0.75.1
 *  `dist/acp-agent.js:6493-6502`). `cachedInputTokens` is cache READS — the name
 *  differs from `usage.cachedReadTokens` because the shape is shared with
 *  codex-acp; `cachedWriteTokens` is Claude's extra sibling. */
export type AcpQuotaTokenCount = {
	totalTokens?: number | null;
	inputTokens?: number | null;
	cachedInputTokens?: number | null;
	cachedWriteTokens?: number | null;
	outputTokens?: number | null;
};

export type AcpPromptResponse = {
	stopReason?: string;
	usage?: AcpWireUsage | null;
	/** Vendor-private, version-pinned. `_meta` is a standard ACP extension slot
	 *  whose values a client may not assume, and `quota` is NOT in
	 *  claude-agent-acp's exported types — it is produced by the private
	 *  `turnQuotaMeta()` (read at 0.75.1 `dist/acp-agent.js:6476-6485`). Read
	 *  defensively, never structurally required, and re-measure on a pin move. */
	_meta?: {
		quota?: {
			token_count?: AcpQuotaTokenCount | null;
			model_usage?: ReadonlyArray<{ model?: string; token_count?: AcpQuotaTokenCount | null }> | null;
		} | null;
	} | null;
};

/** The subset of the ACP agent connection the backend drives (real or fake). */
export interface AcpConnectionLike {
	initialize(params: unknown): Promise<unknown>;
	newSession(params: unknown): Promise<{ sessionId?: string }>;
	prompt(params: { sessionId: string; prompt: AcpTextBlock[] }): Promise<AcpPromptResponse>;
	setSessionConfigOption?(params: unknown): Promise<unknown>;
	/**
	 * ACP `session/cancel` — the PROTOCOL way to end an in-flight prompt turn.
	 *
	 * The spec requires the agent to answer the pending `session/prompt` with
	 * `stopReason: "cancelled"` after this notification, so a user abort ends the
	 * turn as a protocol event (backend.ts maps cancelled → aborted) instead of a
	 * signal race. Fire-and-forget by contract: it is a JSON-RPC notification, so
	 * there is nothing to await and a send failure on an already-closed connection
	 * must not mask the abort the caller is executing.
	 */
	cancel?(params: { sessionId: string }): void;
	/**
	 * Closes the underlying SDK connection before child process teardown. With
	 * the fluent SDK connection this is load-bearing: otherwise a successful
	 * live turn can print PASS but keep Node's event loop alive.
	 *
	 * Implementations MUST be best-effort (never throw): callers invoke it on
	 * success, error, and reuse-error teardown paths, so a close failure must not
	 * mask the turn's real outcome nor skip the child teardown that follows it.
	 */
	close?(error?: unknown): void;
}

/** The ACP client-side callbacks. They delegate to the session's mutable handler. */
export interface AcpClientHandlers {
	sessionUpdate(notification: { update?: Record<string, unknown>; sessionId?: string }): Promise<void>;
	requestPermission(request: { options?: Array<{ optionId: string; kind?: string }> }): Promise<{
		outcome: { outcome: "selected"; optionId: string } | { outcome: "cancelled" };
	}>;
	readTextFile(request: { path: string }): Promise<{ content: string }>;
	// `void` (not `never`): the backend's handler denies by throwing, but the
	// shared smokes legitimately return a write response ({}); both satisfy the
	// SDK's `WriteTextFileResponse | void` handler contract.
	writeTextFile(request: unknown): Promise<void>;
}

/**
 * Production factory — wrap the SDK 1.1 fluent `client()` into the
 * `AcpConnectionLike` seam the backend (and the live smokes) drive.
 *
 * Client-side handlers register by ACP method name; agent-side calls go through
 * the persistent connection's `ClientContext` (`conn.agent`). Both the params a
 * handler receives (`ctx.params`) and the throw-to-JSON-RPC-error behaviour
 * match the deprecated `ClientSideConnection`, so this is behaviour-preserving.
 */
export function connectAcpClient(stream: Stream, handlers: AcpClientHandlers): AcpConnectionLike {
	const conn = client({ name: "entwurf" })
		.onNotification(CLIENT_METHODS.session_update, (ctx) => handlers.sessionUpdate(ctx.params as never))
		.onRequest(CLIENT_METHODS.session_request_permission, (ctx) => handlers.requestPermission(ctx.params as never))
		.onRequest(CLIENT_METHODS.fs_read_text_file, (ctx) => handlers.readTextFile(ctx.params as never))
		.onRequest(CLIENT_METHODS.fs_write_text_file, (ctx) => handlers.writeTextFile(ctx.params as never))
		.connect(stream);

	const agent = conn.agent;
	return {
		initialize: (params) => agent.request(AGENT_METHODS.initialize, params as never),
		newSession: (params) =>
			agent.request(AGENT_METHODS.session_new, params as never) as Promise<{ sessionId?: string }>,
		prompt: (params) => agent.request(AGENT_METHODS.session_prompt, params as never) as Promise<AcpPromptResponse>,
		setSessionConfigOption: (params) => agent.request(AGENT_METHODS.session_set_config_option, params as never),
		cancel: (params) => {
			// Notification, not a request: nothing resolves it, and the connection
			// may already be closing when the operator aborts. Swallow both the sync
			// throw and the rejected send — the caller's abort path continues either
			// way (it escalates to teardown after a bounded grace).
			try {
				void Promise.resolve(agent.notify(AGENT_METHODS.session_cancel, params as never)).catch(() => {});
			} catch {
				// connection already closed — the abort path escalates on its own.
			}
		},
		close: (error) => {
			// Best-effort by contract (see AcpConnectionLike.close): a teardown-path
			// close that threw would mask the turn's real error and skip the child
			// teardown that runs after it.
			try {
				conn.close(error);
			} catch {
				// connection already closed / SDK teardown race — nothing to recover.
			}
		},
	};
}
