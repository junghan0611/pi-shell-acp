// ACP plugin — real streamSimple backend: in-memory session reuse (S2d-1b-2b)
// + billing carrier + first-user augment (S2d-1c).
//
// S2c opened the provider path as spawn-per-turn: every streamSimple call spawned
// a FRESH ACP session and tore it down. S2d-1b-2b adds in-memory session REUSE
// for long-lived (process-scoped) pi processes so a resident does not pay a full
// spawn+initialize+newSession on every turn and so the model keeps its own ACP
// history across turns (the delta-only prompt scope — 핀4).
//
// Two orthogonal axes (GPT 73b44d):
//   - bootstrapPath (history source): `new` sends the FULL transcript (a fresh ACP
//     session holds no history); `reuse` sends only the latest user delta (the
//     live ACP session already remembers the prior turns — re-sending the whole
//     transcript would duplicate history). buildAcpPrompt() owns that split.
//   - lifecyclePolicy (does the child outlive the turn): `process-scoped`
//     (`--entwurf-control` resident) MAY keep the child + connection in an
//     in-memory map and reuse it; `turn-scoped` (`pi -p` one-shot AND plain
//     interactive) is ALWAYS `new` + teardown — a surviving child's stdio handle
//     would pin a one-shot pi's exit (the S2c hang).
//
// Scope of THIS cut (GPT 73b44d / c617cb):
//   - in-memory reuse + new ONLY. Persisted resume/load is the next lane (1b-2c):
//     the record is WRITTEN (so 1b-2c can use it) but never READ/used here, and no
//     resume/load capability is passed to decideBootstrap.
//   - S2d-1c carrier + augment: the engraving carrier (`_meta.systemPrompt`,
//     SHORT, NON-EMPTY by default → v1 preset-replacement memory-containment
//     lever) feeds BOTH the config signature and the session meta from one
//     rendered string; the rich first-user augment (bridge identity + AGENTS + pi
//     base) is prepended to the `new` prompt ONLY, on the wire, so it never enters
//     the reuse-compat signature.
//
// CRITICAL — mutable activePromptHandler routing: a retained ACP connection
// outlives the turn, so its sessionUpdate/requestPermission callbacks must NOT
// close over the first turn's stream state (turn 2's notifications would leak into
// turn 1's finished stream). The callbacks delegate to a MUTABLE
// `session.activePromptHandler` that each turn sets to its own stream state and
// clears in finally.
//
// Errors are encoded into the RETURNED event stream as an `error` event with a
// final assistant message — never thrown after the stream is returned (the
// AssistantMessageEventStream contract).

import { type ChildProcessByStdio, spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { Readable, Writable } from "node:stream";
import { ndJsonStream, PROTOCOL_VERSION } from "@agentclientprotocol/sdk";
import type { Api, AssistantMessage, Context, Model, SimpleStreamOptions } from "@earendil-works/pi-ai";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";
import {
	type AcpClientHandlers,
	type AcpConnectionLike,
	type AcpPromptResponse,
	connectAcpClient,
} from "./acp-client.js";
import { prependNewPromptAugment } from "./augment.js";
import { type AcpBackendAdapter, resolveAcpBackendAdapter } from "./backend-adapter.js";
import {
	enrichMcpServersWithEnvelope,
	mcpServerNames,
	type ResolvedAcpConfig,
	resolveProviderConfig,
} from "./config.js";
import { type AcpTextBlock, buildAcpPrompt } from "./context.js";
import {
	type AcpPiStreamState,
	applyAcpSessionUpdate,
	createAcpStreamState,
	finalizeAcpStreamState,
	pushAcpLifecycleNotice,
	pushPermissionNotice,
} from "./event-mapper.js";
import {
	type BootstrapDecision,
	type BootstrapParams,
	bridgeConfigSignature,
	buildSessionRecord,
	contextMessageSignatures,
	decideBootstrap,
	type ExistingSession,
	type LifecyclePolicy,
	resolveLifecyclePolicy,
	writeSessionRecord,
} from "./session-store.js";
import { assertExcludeToolsHonored, PI_BUILTIN_BACKED_TOOLS } from "./tool-surface.js";

// Bootstrap boundaries ONLY. initialize / newSession / set-model are handshake
// steps that make no model progress, so a stuck one is a dead session and a cold
// retry costs nothing — a wall-clock bound is honest there.
//
// There is deliberately NO prompt boundary. A running turn is not a failure for
// having taken long: tool use, reasoning, and provider queueing all legitimately
// outlive any number we could pick, and the previous 600s absolute cutoff killed
// turns that were still actively producing tool calls. Worse, the cutoff's own
// message ("prompt timed out after 600000ms") lands inside pi's transient-error
// dictionary (`RETRYABLE_PROVIDER_ERROR_PATTERN` in @earendil-works/pi-ai
// `utils/retry.ts` matches `timed? out` / `timeout`), so pi replayed the SAME
// full prompt from a cold ACP session up to `retry.maxRetries` times — paying the
// whole turn again to arrive at the same wall. Elapsed time is not evidence.
// A prompt now ends only on lifecycle events: it resolves, the operator aborts,
// or the child dies / its stdio ends (see awaitAcpPromptTurn).
const INITIALIZE_TIMEOUT_MS = 30_000;
const NEW_SESSION_TIMEOUT_MS = 30_000;
const SET_MODEL_TIMEOUT_MS = 30_000;

// Bounded CLEANUP window after a user abort — not a turn deadline. On abort we
// send the ACP `session/cancel` notification and give the agent this long to
// answer the pending prompt with `cancelled` (the protocol's own ending, which
// maps to aborted). Only if it does not do so within the window do we escalate
// to process-group teardown, so an abort always returns promptly.
const ABORT_CANCEL_GRACE_MS = 5_000;

/** Tokens below which a re-billed prefix is breakpoint granularity, not news.
 *  This matches pi's token threshold for a native cache-miss notice, which also
 *  considers a separate $0.10 cost threshold (read at pi-coding-agent
 *  `dist/modes/interactive/interactive-mode.js:3130`). */
const CACHE_MISS_NOTICE_FLOOR_TOKENS = 20_000;

/** ONE turn's ACCOUNTING totals: the SUM over that turn's API round trips, as
 *  ACP reports them. Carried on `usage.acp`, never on pi's four `Usage` fields —
 *  those mean one REQUEST's prompt shape to readers that would misread a sum
 *  (see `sealTurnUsage`). This is the vendor's own arithmetic, relayed. */
interface AcpTurnAccounting {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
}

function finiteOrZero(value: unknown): number {
	return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/**
 * ONE turn's ACCOUNTING totals, preferring the widest scope the backend offers.
 *
 * `_meta.quota.model_usage` comes from `result.modelUsage` and the vendor calls it
 * "the accounting-grade figure per the SDK" — it also counts Task subagents,
 * sidechains, and INTERNAL CALLS SUCH AS COMPACTION, so its rows "can total more
 * than `token_count`" and are "the fuller picture, not a decomposition of it"
 * (read at claude-agent-acp 0.75.1 `dist/acp-agent.js:6465-6485`). The narrower
 * `PromptResponse.usage` (== `quota.token_count`) is the MAIN AGENT LOOP only.
 *
 * The wider one is the right numerator because the denominator already has that
 * scope: `usage.cost.total` is the diff of the backend's running total, which
 * includes those internal calls. Pairing a main-loop token sum with an
 * all-inclusive cost understates the cache-effect badge exactly when compaction
 * ran — and compaction is a live path again (#94). Rows are summed because a
 * session may in principle report more than one model; with GLG's single-model
 * rule there is exactly one.
 *
 * Falls back to `usage` when the sidecar is absent: `_meta` is a standard ACP
 * extension slot whose contents a client may not assume, and `quota` is not in
 * claude-agent-acp's exported types (#96 carries the re-measure-on-bump duty).
 */
function readTurnAccounting(promptResult: AcpPromptResponse): AcpTurnAccounting | undefined {
	const rows = promptResult?._meta?.quota?.model_usage;
	if (Array.isArray(rows) && rows.length > 0) {
		const total = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
		for (const row of rows) {
			const t = row?.token_count;
			if (!t) continue;
			total.input += finiteOrZero(t.inputTokens);
			total.output += finiteOrZero(t.outputTokens);
			total.cacheRead += finiteOrZero(t.cachedInputTokens);
			total.cacheWrite += finiteOrZero(t.cachedWriteTokens);
		}
		return total;
	}
	const wire = promptResult?.usage;
	if (!wire) return undefined;
	return {
		input: finiteOrZero(wire.inputTokens),
		output: finiteOrZero(wire.outputTokens),
		cacheRead: finiteOrZero(wire.cachedReadTokens),
		cacheWrite: finiteOrZero(wire.cachedWriteTokens),
	};
}

/**
 * The MAIN AGENT LOOP's token totals (`PromptResponse.usage` ==
 * `quota.token_count`). Same four fields as `readTurnAccounting`, different
 * scope: this excludes Task subagents, sidechains, and internal calls such
 * as compaction. The cache-miss bound's recurrence is a MAIN-LOOP identity
 * — occupancy is main-context occupancy — so its IO terms come from here,
 * never from the wide rows. Reporting still uses `readTurnAccounting`.
 */
function readMainLoopAccounting(promptResult: AcpPromptResponse): AcpTurnAccounting | undefined {
	const wire = promptResult?.usage;
	if (!wire) return undefined;
	return {
		input: finiteOrZero(wire.inputTokens),
		output: finiteOrZero(wire.outputTokens),
		cacheRead: finiteOrZero(wire.cachedReadTokens),
		cacheWrite: finiteOrZero(wire.cachedWriteTokens),
	};
}

/** 191,971 → "192k". Keeps the notice inside the 80-char fragment cap. */
function formatTokenCount(tokens: number): string {
	return tokens >= 1000 ? `${Math.round(tokens / 1000)}k` : String(Math.round(tokens));
}

type StdioChild = ChildProcessByStdio<Writable, Readable, Readable>;

// ---------------------------------------------------------------------------
// Injectable seam (deterministic gates) — production wires the real spawn /
// connection; check-acp-session-reuse injects fakes so it can drive two turns
// and CAPTURE the prompt payloads without launching a real ACP child.
// ---------------------------------------------------------------------------

/** The subset of the spawned child the backend touches (real or fake). */
export interface AcpChildLike {
	pid?: number | null;
	exitCode: number | null;
	signalCode: NodeJS.Signals | null;
	stdin: { destroy(): void; unref?(): void };
	stdout: { destroy(): void; unref?(): void };
	stderr: {
		on(event: "data", listener: (chunk: Buffer) => void): void;
		/** Optional: absent on minimal fakes; the flush is best-effort, never load-bearing for liveness. */
		once?(event: "close", listener: () => void): void;
		destroy(): void;
		unref?(): void;
	};
	kill(signal?: NodeJS.Signals | number): boolean;
	unref(): void;
	once(event: "exit" | "error", listener: (...args: unknown[]) => void): void;
}

// AcpConnectionLike / AcpClientHandlers (the connection seam the backend drives
// and the gate fakes) now live in ./acp-client.ts alongside the connectAcpClient
// factory that builds the real one — imported above.

/** Backend dependencies — defaulted to the real implementations, faked in gates. */
export interface AcpTurnDeps {
	spawnChild(launch: { command: string; args: string[] }, cwd: string, extraEnv: Record<string, string>): AcpChildLike;
	createConnection(child: AcpChildLike, handlers: AcpClientHandlers): AcpConnectionLike;
	lifecyclePolicy(): LifecyclePolicy;
	/** Resolve operator provider config (S2g). Real impl reads global+project settings.
	 *  Takes the already-routed `adapter` (resolved once at turn entry) so the backend
	 *  can parse its OWN settings without config.ts re-routing — the model id stays the
	 *  single routing authority. */
	loadConfig(cwd: string, modelId: string, adapter: AcpBackendAdapter): ResolvedAcpConfig;
	now(): string;
	/** Record dir override (tests). Defaults to the real session cache dir. */
	sessionDir?: string;
	/**
	 * Post-abort cleanup grace (gates). Defaults to ABORT_CANCEL_GRACE_MS. This is
	 * the ONLY injectable clock left on the turn path and it bounds cleanup after
	 * an abort — never a running prompt.
	 */
	abortGraceMs?: number;
}

// ---------------------------------------------------------------------------
// In-memory session registry (process-scoped reuse) + global cleanup
// ---------------------------------------------------------------------------

interface AcpBridgeEvent {
	type: "session_notification" | "permission_request";
	update?: Record<string, unknown>;
	sessionId?: string;
	decision?: "approved" | "cancelled";
}

/**
 * A one-shot latch for "the child has ended", created at spawn and settled by
 * `onChildGone`. `settled` answers the question with no waiting at all; the
 * promise is only for the bounded post-mortem window (settleChildEnd).
 */
interface ChildEndLatch {
	settled: boolean;
	promise: Promise<void>;
	/** Called exactly once by onChildGone; cleared so a second end is a no-op. */
	settle?: () => void;
}

function makeChildEndLatch(): ChildEndLatch {
	let settle!: () => void;
	const promise = new Promise<void>((resolve) => {
		settle = resolve;
	});
	const latch: ChildEndLatch = {
		settled: false,
		promise,
		settle: () => {
			latch.settled = true;
			latch.settle = undefined;
			settle();
		},
	};
	return latch;
}

interface BridgeSession {
	key: string;
	cwd: string;
	modelId: string;
	child: AcpChildLike;
	connection: AcpConnectionLike;
	acpSessionId: string;
	bridgeConfigSignature: string;
	contextMessageSignatures: string[];
	alive: boolean;
	busy: boolean;
	/** Mutable per-turn router — see the CRITICAL note in the file header. */
	activePromptHandler?: (event: AcpBridgeEvent) => void;
	/**
	 * The child's own dying words, SESSION-scoped on purpose. The stderr drain is
	 * installed once at spawn; keeping the buffer on the turn that spawned would
	 * leave every later reuse turn reporting a bare "ACP connection closed" with
	 * nothing to diagnose it by (observed 2026-07-30 on a live sonnet reuse turn).
	 */
	stderrTail: string[];
	/**
	 * SESSION-scoped like `stderrTail`, and for the same reason: the launcher's
	 * frame can arrive on a turn later than the one that spawned the child.
	 */
	launchObservation: AcpLaunchObservation;
	/** How the child ended, once it has — folded into the prompt-phase error. */
	exit?: { code: number | null; signal: NodeJS.Signals | null };
	/**
	 * LATCH for the child's end, readable at ANY time — deliberately not a
	 * callback.
	 *
	 * `notifyChildGone` lives only between the two lines of
	 * `awaitAcpPromptTurn`'s try/finally, so it can carry the exit status only
	 * when the child's `exit` event wins the race against the transport — and on
	 * the shape this backend actually runs, it does not. With piped stdio on
	 * Linux the child's stdout EOF was measured landing about a millisecond BEFORE
	 * node emits `exit`, for a clean exit and for SIGKILL alike (issue #72). The
	 * SDK's generic "ACP connection closed" therefore settles the race first,
	 * `finally` clears the callback, and the exit status arriving one tick later
	 * has nowhere to go — which is how #72's field sample reached the operator
	 * naming neither exit code nor signal. The opposite order stays possible and
	 * is still handled (notifyChildGone), so both are covered by the gate.
	 *
	 * The latch outlives the race: `settled` is the durable fact and `promise`
	 * lets a failing turn wait a BOUNDED moment for a late end (settleChildEnd).
	 */
	childEnd: ChildEndLatch;
	/** Set while a prompt is in flight so a child death can close it (awaitAcpPromptTurn). */
	notifyChildGone?: (err: Error) => void;
	/**
	 * The SDK's last-observed SESSION-CUMULATIVE cost, in USD — the baseline the
	 * NEXT turn's cost is differenced against — authoritative for this rail in
	 * the sense that the backend's own estimate outranks any local recompute,
	 * not in the sense of a billing statement (#93).
	 *
	 * BRIDGE-SESSION SCOPED, and that scope is the invariant. It must track the
	 * live child, because the cumulative it measures is that child's own running
	 * total and restarts at zero with a new one: a rebuilt session (config-signature
	 * drift) gets a fresh object and therefore a fresh baseline, which is exactly
	 * right. Hoisting this to the pi session would keep a dead child's total as the
	 * baseline and make the next real turn's diff enormous or negative.
	 *
	 * `undefined` = no cumulative observed yet, which is NOT the same as 0: a turn
	 * that reports no cost must HOLD this value, not zero it, or the amount it
	 * carried would be double-counted by the next diff.
	 */
	sdkCumulativeCostUsd?: number;
	/**
	 * The last observed context OCCUPANCY (`usage_update.used`), carried forward
	 * across a turn whose notification never arrived (#93).
	 *
	 * Without this, such a turn carries accounting at `usage.acp` but has zero
	 * `totalTokens` and zero pi-native usage fields. pi's
	 * `calculateContextTokens` (read at pi-coding-agent
	 * `dist/core/compaction/compaction.js:86-88`) then returns 0, making
	 * auto-compaction replace the vendor observation with its local estimate
	 * (read at pi-coding-agent `dist/core/agent-session.js:1696-1699`). Carrying
	 * the last measurement preserves the last known occupancy. Assigned, never
	 * summed.
	 */
	contextOccupancyTokens?: number;
	/**
	 * The PREVIOUS turn's MAIN-LOOP `Σinput + Σoutput` (`PromptResponse.usage`,
	 * never the wide `model_usage` sum) and the wall-clock ms at which that
	 * turn SEALED. The idle gap is then measured from that seal to THIS turn's
	 * START (`turnStartedAtMs`), never to its seal, so a turn's own duration can
	 * never inflate the gap it reports. Together with `contextOccupancyTokens`,
	 * they are the whole input to the cache-miss bound in `sealTurnUsage` — no
	 * per-round-trip collection.
	 *
	 * Why these two and nothing else: within one turn Claude Code's cache
	 * breakpoints make `cacheRead_i = cacheRead_(i-1) + cacheWrite_(i-1)`
	 * (re-measured 2026-09-02 across the WHOLE ACP overlay corpus, not one ledger:
	 * 2,398 of 2,410 adjacent pairs hold — 99.50% — over 30+ session transcripts
	 * under `~/.pi/agent/claude-config-overlay/projects` spanning 2026-05 to
	 * 2026-09. On the incident ledger alone it is 101 of 102, and that single break
	 * IS the miss: cacheRead 0 against a predicted 195,177 at 2026-09-01T21:15:09Z.
	 * Of the 12 corpus-wide breaks, 10 fall BELOW prediction — each one a real miss
	 * or partial re-read — and the 2 that exceed it do so by 4,357 and 3,283 tokens,
	 * both far under the notice floor, so neither could lift a quiet turn over the
	 * threshold on its own). Telescoping that identity gives
	 *
	 *     cacheRead_first = used_end − ΣcacheWrite − (input_last + output_last)
	 *
	 * and the same identity on the previous turn gives what THIS turn's first
	 * request would have read had the cache still been warm:
	 *
	 *     expected = used_prev − (input_last' + output_last')
	 *
	 * Only the LAST request's input+output is unknown at turn scope, and it is
	 * bounded by the turn's own sums — so both quantities come out as PROVEN
	 * INTERVALS, never estimates. Assigned, never summed.
	 */
	priorTurnInputOutputSum?: number;
	priorTurnSealedAtMs?: number;
	/**
	 * This TURN owns reporting the child's end, so the next turn must not also
	 * announce it. Raised at the top of a failure path — BEFORE the bounded
	 * settle and before any teardown — so an end observed during that window is
	 * still a natural one (we have not signalled anything yet) but is reported
	 * exactly once, by the turn that failed on it.
	 */
	reporting?: boolean;
	/**
	 * We are tearing this child down ON PURPOSE (turn-scoped teardown, config
	 * drift, error/abort cleanup). Its exit is then expected, not news: without
	 * this flag every ordinary turn-scoped turn would announce its own routine
	 * teardown to the NEXT turn as if the session had died.
	 */
	retiring?: boolean;
}

const bridgeSessions = new Map<string, BridgeSession>();
const retainedChildren = new Set<AcpChildLike>();
// sessionKeys with a prompt currently in flight. A NEW turn does not enter
// bridgeSessions until it succeeds, so without this a second concurrent FIRST
// turn for the same key would also see `existing === undefined` and spawn a
// second child. Claimed before spawn, released in the orchestrator finally
// (GPT blocker 1).
const inFlightKeys = new Set<string>();
let cleanupRegistered = false;

/**
 * Register ONE global `exit` hook that SIGKILLs every retained child's group, so
 * a resident pi never orphans the `claude` grandchildren. A per-session
 * `process.once` would leak an EventEmitter listener per turn — GPT c617cb. The
 * handler is sync (the `exit` event forbids async work).
 */
function registerGlobalCleanup(): void {
	if (cleanupRegistered) return;
	cleanupRegistered = true;
	process.once("exit", () => {
		for (const child of retainedChildren) killChildGroup(child, "SIGKILL");
	});
}

/**
 * The child died: mark dead + drop from map + retained set, RECORD how it ended,
 * and close any prompt that was waiting on it. Without that last step a
 * mid-prompt death is only observable through the SDK's generic "ACP connection
 * closed" rejection, which names neither the exit status nor the stderr.
 */
function onChildGone(session: BridgeSession, exit?: { code: number | null; signal: NodeJS.Signals | null }): void {
	session.alive = false;
	if (exit) session.exit = exit;
	if (bridgeSessions.get(session.key) === session) bridgeSessions.delete(session.key);
	retainedChildren.delete(session.child);
	// Close the latch FIRST and unconditionally: it is the durable fact, and a
	// failing turn may already be waiting on it inside its bounded settle window.
	session.childEnd.settle?.();
	if (session.notifyChildGone) {
		// A turn was waiting on this child — it reports the death itself.
		session.notifyChildGone(childEndedError(session));
	} else if (!session.retiring && !session.reporting) {
		// Died BETWEEN turns with no turn to fail and nobody tearing it down, so
		// nobody has seen it. Without this the next turn would silently open a
		// fresh child and read as an ordinary cold start, hiding that the backend
		// session the operator was talking to is gone. A DELIBERATE teardown is
		// excluded — announcing our own routine cleanup would be noise, not news.
		unreportedChildEnds.set(session.key, session.exit ?? { code: null, signal: null });
	}
}

/** Deaths no turn observed, keyed by sessionKey and announced once by the next turn. */
const unreportedChildEnds = new Map<string, { code: number | null; signal: NodeJS.Signals | null }>();

/** Read-and-clear: an unreported death is announced exactly once. */
function takeUnreportedChildEnd(
	sessionKey: string,
): { code: number | null; signal: NodeJS.Signals | null } | undefined {
	const end = unreportedChildEnds.get(sessionKey);
	if (end) unreportedChildEnds.delete(sessionKey);
	return end;
}

/** "exit code 1" / "signal SIGKILL" / "exit code 0, signal SIGTERM" / "no exit status". */
function describeChildEnd(exit?: { code: number | null; signal: NodeJS.Signals | null }): string {
	if (!exit) return "no exit status";
	const parts = [
		exit.code !== null ? `exit code ${exit.code}` : undefined,
		exit.signal ? `signal ${exit.signal}` : undefined,
	].filter(Boolean);
	return parts.length > 0 ? parts.join(", ") : "no exit status";
}

/**
 * The prompt-phase error for a child that died under a live turn.
 *
 * Wording is load-bearing: pi classifies a failed assistant message by matching
 * its errorMessage against `RETRYABLE_PROVIDER_ERROR_PATTERN`, so anything we
 * author here that reads like "timed out" / "timeout" / "terminated" /
 * "connection lost" would put a full cold prompt replay back on the table. This
 * text names the lifecycle fact and nothing that looks transient.
 * (The appended backend stderr tail is the child's text, not ours.)
 */
function childEndedError(session: BridgeSession): Error {
	return new Error(
		`entwurf: the ACP backend process ended while the prompt was still in flight (${describeChildEnd(session.exit)}) — ` +
			"this turn has no answer",
	);
}

/**
 * The BOUNDED post-mortem window a turn that ALREADY failed may wait for the
 * child's exit status.
 *
 * This is NOT a prompt deadline and must never become one: nothing here can end
 * a running turn. It opens only after the prompt has already settled as a
 * transport closure, and it closes on the child's own `exit` — which follows the
 * stdout EOF by about a millisecond, so this is headroom, not a felt wait.
 */
const CHILD_END_SETTLE_MS = 500;

/**
 * The SDK's exact words for "the transport ended under a pending request"
 * (`@agentclientprotocol/sdk` jsonrpc.js / acp.js:
 * `closeSignal.reason ?? new Error("ACP connection closed")`).
 *
 * Matched EXACTLY, not by substring: this text appears only when the close
 * carried NO reason — a clean stdout EOF rather than an errored stream — which
 * is the one failure shape that arrives with no lifecycle facts of its own. A
 * close that DID carry a reason already explains itself and must not be given a
 * settle delay, and our own `childEndedError` already names the exit status.
 * Widening this to a substring test would put that delay on errors that do not
 * need it.
 */
const ACP_CONNECTION_CLOSED_TEXT = "ACP connection closed";

/**
 * The launcher's control frame — see `claude-acp-launch.js`.
 *
 * Matched as an EXACT FULL LINE and nothing else. The vendor writes prose that
 * mentions signals; a substring test would let vendor text manufacture an
 * entwurf observation, which is precisely the confusion #72 cost three
 * diagnosis passes. Our own frame is a fixed enum, so exact-line matching is
 * sufficient AND necessary.
 */
const LAUNCH_SIGNAL_FRAME_PREFIX = "ENTWURF_ACP_LAUNCH_SIGNAL=";
const LAUNCH_SIGNAL_FRAME_VALUES: ReadonlySet<string> = new Set(["SIGTERM", "SIGINT"]);

/** A mutable, session-scoped record of a terminating signal the LAUNCHER caught. */
export type AcpLaunchObservation = { signal?: "SIGTERM" | "SIGINT" };

/**
 * Split a stderr chunk stream into lines, consuming our own frames and passing
 * everything else through to the tail untouched.
 *
 * Line-buffered because a chunk boundary can fall inside a frame; the trailing
 * partial line is held, not emitted, so a frame split across two reads is still
 * recognised exactly.
 */
function makeLaunchFrameFilter(observation: AcpLaunchObservation, onText: (text: string) => void) {
	let held = "";
	return {
		write(chunk: string): void {
			held += chunk;
			let nl = held.indexOf("\n");
			let passed = "";
			while (nl !== -1) {
				const line = held.slice(0, nl);
				if (
					line.startsWith(LAUNCH_SIGNAL_FRAME_PREFIX) &&
					LAUNCH_SIGNAL_FRAME_VALUES.has(line.slice(LAUNCH_SIGNAL_FRAME_PREFIX.length))
				) {
					// FIRST caught signal wins: a later one is our own teardown racing
					// the external kill, and reporting that would bury the cause.
					observation.signal ??= line.slice(LAUNCH_SIGNAL_FRAME_PREFIX.length) as "SIGTERM" | "SIGINT";
				} else {
					passed += `${line}\n`;
				}
				held = held.slice(nl + 1);
				nl = held.indexOf("\n");
			}
			if (passed) onText(passed);
		},
		/**
		 * The child's LAST words may arrive without a trailing newline — a process
		 * dying mid-write is exactly when that happens, and it is exactly when the
		 * tail matters most. Line buffering would otherwise hold that fragment
		 * forever, so the stream's close flushes it VERBATIM.
		 *
		 * No frame check here, deliberately: the launcher writes its frame with a
		 * single `writeSync` including the newline, well under PIPE_BUF, so a
		 * complete frame can never be the un-terminated remainder. Anything left
		 * without a newline is vendor text by construction.
		 */
		flush(): void {
			if (!held) return;
			onText(held);
			held = "";
		},
	};
}

/**
 * What the operator is told about a caught signal — and what they are NOT told.
 *
 * Absence is reported as "not observed", never as "no signal": the launcher can
 * only see what reached it, and an override launch (`CLAUDE_AGENT_ACP_COMMAND`)
 * has no launcher at all. Attribution of the SENDER is not claimed here either —
 * that needs the host's journal, which this process cannot read.
 */
function launchSignalLine(observation: AcpLaunchObservation | undefined): string | undefined {
	if (!observation?.signal) return undefined;
	return `[acp] launch observed ${observation.signal} before child exit (sender not attributed)`;
}

function isAcpConnectionClosure(err: unknown): boolean {
	const message = err instanceof Error ? err.message : typeof err === "string" ? err : "";
	return message.trim() === ACP_CONNECTION_CLOSED_TEXT;
}

/**
 * Wait a BOUNDED moment for a child end that the transport already implied.
 *
 * Resolves immediately when the latch is already closed (the common case once
 * the ~1ms gap has passed) and never rejects. The timer is deliberately NOT
 * unref'd: it is the only thing that ends this wait, so letting the loop drain
 * past it would leave a failing turn unsealed — the opposite of the honesty this
 * exists for. It is cleared on both exits, so it holds nothing open.
 */
async function settleChildEnd(latch: ChildEndLatch, ms: number): Promise<void> {
	if (latch.settled) return;
	let timer: ReturnType<typeof setTimeout> | undefined;
	try {
		await Promise.race([
			latch.promise,
			new Promise<void>((resolve) => {
				timer = setTimeout(resolve, ms);
			}),
		]);
	} finally {
		if (timer) clearTimeout(timer);
	}
}

/**
 * The lifecycle line appended to a transport-closure failure, so the operator
 * reads WHICH phase died and HOW the child ended.
 *
 * Wording is load-bearing for the same reason `childEndedError`'s is: pi
 * classifies a failed assistant message against `RETRYABLE_PROVIDER_ERROR_PATTERN`
 * (@earendil-works/pi-ai `utils/retry`), whose terms include "timed out",
 * "timeout", "terminated", "connection lost" and "ended without". None of those
 * may appear here, or a dead child would put a full cold prompt replay back on
 * the table — with the tool side effects this turn already produced.
 *
 * That pattern is a bare substring alternation (`new RegExp(terms.join("|"), "i")`
 * — NO word boundaries) and its terms enumerate the HTTP statuses "429", "500",
 * "502", "503", "504" and "524". So the settle bound is deliberately NOT interpolated: rendering
 * CHILD_END_SETTLE_MS made this line say "within 500ms", which pi read as an
 * HTTP 500 and classified as transient. Naming the window in prose keeps a later
 * change of that constant from silently re-arming the replay — do not "improve"
 * this by putting the number back; the bound belongs in the code and the gate.
 *
 * The three endings are kept DISTINCT on purpose (issue #72 Done-when): an
 * exit code, a signal, and "we waited and it never said" are three different
 * facts, and collapsing them is what made the original sample unreadable.
 */
function childEndLifecycleLine(opts: {
	/** "pre-prompt" covers a new turn's bootstrap AND a reuse turn's pre-send steps. */
	phase: "pre-prompt" | "prompt";
	exit?: { code: number | null; signal: NodeJS.Signals | null };
	ended: boolean;
}): string {
	const where =
		opts.phase === "prompt"
			? "the ACP backend connection closed while the prompt was still in flight"
			: "the ACP backend connection closed before this turn's prompt was sent";
	const how = opts.ended
		? `the child ended (${describeChildEnd(opts.exit)})`
		: "the child reported no exit status within the bounded post-mortem window";
	return `[acp] lifecycle: ${where} — ${how}; this turn has no answer`;
}

/**
 * The failure path's post-mortem: enrich ONLY the transport-closure shape, and
 * only after waiting a bounded moment for the exit status the close implies.
 *
 * Returns `undefined` for every other failure — an abort, a bootstrap throw, or
 * a child death our own `notifyChildGone` already diagnosed — so no other error
 * pays a delay and none is double-reported.
 *
 * Callers MUST run this BEFORE tearing the child down: our teardown SIGTERMs the
 * process group, so an exit read after it would be OUR signal recorded as the
 * child's cause of death.
 *
 * The stderr claim is deliberately NARROW. Running before teardown means the tail
 * already collected is not cut short by our own cleanup, and stderr arriving
 * during this window still lands in it. It does NOT promise the child's last
 * words: node's `exit` can precede the stdio drain, and nothing here waits for
 * the stderr pipe to close. Draining it is a separate lever, not this one.
 */
async function diagnoseTransportClosure(opts: {
	err: unknown;
	session: BridgeSession | undefined;
	phase: "pre-prompt" | "prompt";
	aborted: boolean;
}): Promise<string | undefined> {
	if (opts.aborted || !opts.session) return undefined;
	if (!isAcpConnectionClosure(opts.err)) return undefined;
	const session = opts.session;
	// This turn owns the announcement from here on, so the next turn must not
	// repeat it. Raised BEFORE the wait and before any signal of ours, so an end
	// observed inside the window is still a natural one.
	session.reporting = true;
	await settleChildEnd(session.childEnd, CHILD_END_SETTLE_MS);
	return childEndLifecycleLine({
		phase: opts.phase,
		exit: session.exit,
		ended: session.childEnd.settled,
	});
}

// ---------------------------------------------------------------------------
// timeout / launch / permission / stopReason / teardown helpers
// ---------------------------------------------------------------------------

// Race a BOOTSTRAP phase against its timeout, ALWAYS clearing the timer
// afterwards. A naive `Promise.race([p, sleep(ms)])` leaves the timer pending
// when `p` wins — a dangling timer that keeps pi's event loop alive long after
// the turn, so pi would never exit a `-p` run. clearTimeout in finally fixes it.
// Only initialize / newSession / set-model use this; the prompt has no deadline.
function withTimeout<T>(label: string, p: Promise<T>, ms: number): Promise<T> {
	let timer: ReturnType<typeof setTimeout> | undefined;
	const timeout = new Promise<never>((_, reject) => {
		timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
		timer.unref?.();
	});
	return Promise.race([p, timeout]).finally(() => {
		if (timer) clearTimeout(timer);
	});
}

/**
 * Await ONE ACP prompt with NO wall-clock deadline — the turn ends on lifecycle
 * events only. Shared by the new and the reuse turn so both close the same way.
 *
 * The three endings:
 *
 *   resolve      the agent answered `session/prompt` (any stopReason — the
 *                verdict mapping is the caller's job).
 *   child gone   the child exited or its stdio ended. Both are already fatal to
 *                the request — the SDK rejects every pending response when the
 *                read loop hits EOF — but the SDK's own error says only "ACP
 *                connection closed". `notifyChildGone` gets there first with the
 *                exit status, and the caller appends the session stderr tail.
 *   abort        the operator cancelled. We send ACP `session/cancel` and let
 *                the agent end its own turn (`cancelled` → aborted). Escalation
 *                to process-group teardown happens only after a bounded grace,
 *                and closing the connection rejects the pending request, so an
 *                abort is always answered even against a wedged child.
 *
 * A stalled-but-alive child is deliberately NOT an ending: a silent turn is not
 * a failed turn, and nothing here may kill one for being quiet.
 */
async function awaitAcpPromptTurn(
	session: BridgeSession,
	promptArgs: { sessionId: string; prompt: AcpTextBlock[] },
	opts: { signal?: AbortSignal; graceMs: number },
): Promise<AcpPromptResponse> {
	let rejectLifecycle: ((err: Error) => void) | undefined;
	const lifecycle = new Promise<never>((_, reject) => {
		rejectLifecycle = reject;
	});
	// The race's loser stays pending forever when the prompt wins; a rejection
	// nobody observed would surface as an unhandled rejection at that point.
	lifecycle.catch(() => {});

	let graceTimer: ReturnType<typeof setTimeout> | undefined;
	const escalateAbort = (): void => {
		killChildGroup(session.child, "SIGTERM");
		// Closing rejects the still-pending ACP request, so the await below settles
		// even when the child ignores both the cancel notification and the signal.
		session.connection.close?.(new Error("entwurf: ACP prompt cancelled by the operator"));
		rejectLifecycle?.(new Error("entwurf: the ACP prompt was cancelled by the operator"));
	};
	const onAbort = (): void => {
		try {
			session.connection.cancel?.({ sessionId: promptArgs.sessionId });
		} catch {
			// best-effort: escalation below is what guarantees the abort returns.
		}
		// NOT unref'd, deliberately. This timer is the only thing that finishes an
		// abort against an agent that ignores session/cancel, so letting the event
		// loop drain past it would leave the turn unsettled and the child alive.
		// It is bounded (graceMs) and cleared in the finally below, so the worst it
		// can do is hold an exiting process for that grace — which is the cleanup
		// we asked for.
		graceTimer = setTimeout(escalateAbort, opts.graceMs);
	};

	session.notifyChildGone = (err) => rejectLifecycle?.(err);
	const signal = opts.signal;
	if (signal) {
		if (signal.aborted) onAbort();
		else signal.addEventListener("abort", onAbort, { once: true });
	}

	try {
		return await Promise.race([session.connection.prompt(promptArgs), lifecycle]);
	} finally {
		if (graceTimer) clearTimeout(graceTimer);
		signal?.removeEventListener("abort", onAbort);
		session.notifyChildGone = undefined;
	}
}

/** Approve-all permission policy (YOLO — oracle F). options empty → cancelled. */
function resolvePermissionResponse(params: { options?: Array<{ optionId: string; kind?: string }> }): {
	outcome: { outcome: "selected"; optionId: string } | { outcome: "cancelled" };
} {
	const options = Array.isArray(params?.options) ? params.options : [];
	if (options.length === 0) return { outcome: { outcome: "cancelled" } };
	const allow = options.find((o) => o.kind === "allow_once" || o.kind === "allow_always");
	return { outcome: { outcome: "selected", optionId: (allow ?? options[0]).optionId } };
}

/** Verdict for one ACP prompt result — what pi should report, and why. */
export type AcpStopVerdict = {
	stopReason: AssistantMessage["stopReason"];
	/** The raw ACP reason, preserved whenever the wire carried one. */
	rawStopReason?: string;
	/** Set exactly when `stopReason` is "error" — carries the reason into the UI. */
	errorMessage?: string;
};

/**
 * ACP prompt stopReason → pi verdict.
 *
 * The ACP terminal set is closed (`@agentclientprotocol/sdk` 1.4.0
 * `dist/schema/types.gen.d.ts:3001`): end_turn | max_tokens | max_turn_requests |
 * refusal | cancelled — no `| string` arm. 1.4.0 also ships an OPEN union at
 * `dist/v2/schema/types.gen.d.ts:3607`, but that is behind the `./experimental/v2`
 * export and entwurf imports the bare specifier, which resolves to the closed v1
 * surface. Only three of those are successful or benign ends. The previous
 * implementation returned a bare StopReason with `default: "stop"`, which turned
 * `refusal`, `max_turn_requests`, any future member, AND a missing reason into a
 * clean successful turn — pi then rendered a silently truncated answer as if the
 * model had finished. pi 0.83 closed the same hole in its own providers (#7272:
 * unmapped terminal reasons surface as provider errors, never successful stops)
 * and added `rawStopReason` so the wire value survives the mapping. This mirrors
 * that contract rather than inventing a local one.
 */
export function mapPromptStopReason(stopReason: string | undefined): AcpStopVerdict {
	switch (stopReason) {
		case "end_turn":
			return { stopReason: "stop", rawStopReason: stopReason };
		case "max_tokens":
			return { stopReason: "length", rawStopReason: stopReason };
		case "cancelled":
			return { stopReason: "aborted", rawStopReason: stopReason };
		case "refusal":
			return {
				stopReason: "error",
				rawStopReason: stopReason,
				errorMessage: "ACP backend stopped with: refusal (the model declined to answer; the turn is incomplete)",
			};
		case "max_turn_requests":
			return {
				stopReason: "error",
				rawStopReason: stopReason,
				errorMessage:
					"ACP backend stopped with: max_turn_requests (the backend's per-turn request budget was exhausted; the turn is incomplete)",
			};
		case undefined:
			return {
				stopReason: "error",
				errorMessage: "ACP backend ended the turn without a stop reason",
			};
		default:
			return {
				stopReason: "error",
				rawStopReason: stopReason,
				errorMessage: `ACP backend stopped with an unrecognized reason: ${stopReason}`,
			};
	}
}

// Signal the child's whole PROCESS GROUP. claude-agent-acp spawns a `claude`
// grandchild that inherits the stdio pipe fds; killing only the direct child
// leaves the grandchild holding the write end of pi's stdout pipe, so pi's event
// loop never drains and the process hangs. The child is spawned `detached` (its
// own group), so a negative-pid kill reaches the grandchild too.
function killChildGroup(child: AcpChildLike, signal: NodeJS.Signals): void {
	try {
		if (child.pid != null) process.kill(-child.pid, signal);
		else child.kill(signal);
	} catch {
		try {
			child.kill(signal);
		} catch {
			// already gone
		}
	}
}

// Tear the child down WITHOUT blocking pi's exit. The pi process exits only when
// its event loop has no ref'd handles; the backend child's stdio pipes are such
// handles. Awaiting the child's death (it may be slow to honor SIGTERM, and its
// `claude` grandchild can linger) would pin pi open. Instead we (1) destroy pi's
// own pipe handles immediately so the loop frees, (2) unref the child so it never
// keeps the loop alive, (3) SIGTERM the group now and SIGKILL it after a grace on
// an UNREF'd timer (best-effort reaping that does not itself hold pi open).
//
// REUSE INVARIANT (GPT c617cb): teardownChild is ONLY for turn-scoped one-shots
// and for incompatible/error/abort closes — NEVER between turns of a retained
// process-scoped session (that would destroy the reusable connection's stdio).
function teardownChild(child: AcpChildLike, graceMs = 2_000): void {
	const alreadyDead = child.exitCode !== null || child.signalCode !== null;
	if (!alreadyDead) killChildGroup(child, "SIGTERM");
	for (const s of [child.stdin, child.stdout, child.stderr]) {
		try {
			s?.destroy();
		} catch {
			// best-effort
		}
	}
	try {
		child.unref();
	} catch {
		// best-effort
	}
	if (!alreadyDead) {
		const t = setTimeout(() => killChildGroup(child, "SIGKILL"), graceMs);
		t.unref?.();
	}
}

// unref (NOT destroy) a retained process-scoped child so its live stdio handles
// do not pin pi's event loop. While the resident runs, the control socket (and
// the next turn) keeps the loop alive, so reads still flow and reuse works; on
// resident shutdown the loop can drain to empty so the `exit` cleanup hook fires
// (an un-unref'd stdio handle would re-create the S2c hang at quit). GPT amber.
function unrefRetainedChild(child: AcpChildLike): void {
	try {
		child.unref();
	} catch {
		// best-effort
	}
	for (const s of [child.stdin, child.stdout, child.stderr]) {
		try {
			s?.unref?.();
		} catch {
			// best-effort
		}
	}
}

/** Default (production) dependencies — real spawn + real ACP client connection. */
function defaultDeps(): AcpTurnDeps {
	return {
		spawnChild: (launch, cwd, extraEnv) =>
			spawn(launch.command, launch.args, {
				cwd,
				env: { ...process.env, ...extraEnv },
				stdio: ["pipe", "pipe", "pipe"],
				// Own process group so teardown can signal the claude grandchild too.
				detached: true,
			}) as unknown as AcpChildLike,
		createConnection: (child, handlers) => {
			const real = child as unknown as StdioChild;
			const stdoutWeb = Readable.toWeb(real.stdout) as unknown as ReadableStream<Uint8Array>;
			const stdinWeb = Writable.toWeb(real.stdin) as unknown as WritableStream<Uint8Array>;
			const transport = ndJsonStream(stdinWeb, stdoutWeb);
			return connectAcpClient(transport as unknown as Parameters<typeof connectAcpClient>[0], handlers);
		},
		lifecyclePolicy: () => resolveLifecyclePolicy(),
		loadConfig: (cwd, modelId, adapter) => resolveProviderConfig({ cwd, modelId, adapter }),
		now: () => new Date().toISOString(),
	};
}

/** sessionKey: options.sessionId, else PI_SESSION_ID, else a cwd fallback (GPT ②). */
function resolveSessionKey(opts: { sessionId?: string } | undefined, cwd: string): string {
	const sid = opts?.sessionId?.trim() || process.env.PI_SESSION_ID?.trim();
	return sid ? `pi:${sid}` : `cwd:${cwd}`;
}

/** Best-effort persist of the session record (1b-2c reads it; this cut only writes). */
function persistRecord(session: BridgeSession, deps: AcpTurnDeps): void {
	try {
		const record = buildSessionRecord(
			{
				sessionKey: session.key,
				acpSessionId: session.acpSessionId,
				cwd: session.cwd,
				modelId: session.modelId,
				bridgeConfigSignature: session.bridgeConfigSignature,
				contextMessageSignatures: session.contextMessageSignatures,
			},
			deps.now(),
		);
		writeSessionRecord(record, deps.sessionDir);
	} catch {
		// record is a 1b-2c convenience — a write failure must not fail the turn.
	}
}

// Detour A (A-c) — actionable rendering of a context-window overflow.
//
// An interactive / one-shot entwurf turn is `turn-scoped`, so it is ALWAYS
// `new`: every turn spawns a fresh ACP child and resends the FULL transcript +
// first-user augment as one prompt (there is no persisted resume yet — that is
// the deferred 1b-2c lane). A long, or resumed, conversation can therefore
// exceed the backend model's input window, which the backend returns as a
// terse 400 the operator sees only as "API Error". This pure classifier turns
// that into an honest, actionable hint. It does NOT change routing or suppress
// the error — it only makes the broken state legible (Code Principle: surface
// broken tool state AS broken).
//
// Resume itself is legitimate — entwurf locks the MODEL, not resume — so
// the hint never tells the operator to stop resuming; it names the real cause
// (turn-scoped full-transcript replay) and the real follow-up fix.
const ACP_CONTEXT_OVERFLOW_SIGNATURES: readonly RegExp[] = [
	/prompt is too long/i,
	/input (?:is )?too long/i,
	/input length and `?max_tokens`? exceed/i,
	/(?:maximum|max) context/i,
	/context (?:window|length)/i,
	/too many (?:input )?tokens/i,
	/exceeds? the (?:maximum|context)/i,
	/reduce the length of/i,
];

export function actionableAcpBackendHint(message: string): string | undefined {
	if (!ACP_CONTEXT_OVERFLOW_SIGNATURES.some((re) => re.test(message))) return undefined;
	return [
		"[acp] likely context-window overflow — the backend model rejected the input as too long.",
		"  Why: this turn used a FRESH ACP backend session (common in a turn-scoped / no --entwurf-control",
		"       session, but also a resident's first or incompatible turn), so it resent the FULL transcript",
		"       + augment as one prompt; a long or resumed conversation can exceed the backend model's input",
		"       window. (Resume is legitimate — entwurf locks the model, not resume.)",
		"  Now: start a fresh or shorter session to get unblocked.",
		"  Root fix (follow-up): persisted resume (delta-only) or a window/summary policy.",
	].join("\n");
}

/**
 * pi 0.84 streamSimple hook contract (#63; upstream pi-mono #7372 → doc-only PR
 * #7576): implementations must invoke `options.onPayload` before sending the
 * provider request and use any returned replacement.
 *
 * On this rail the provider request is the ACP `session/prompt` params — so the
 * hook receives the EXACT `{sessionId, prompt}` object after the wire content is
 * fully built (augment / reuse delta included) and immediately before
 * `connection.prompt`. That is the truthful analogue of the built-in providers'
 * post-build/pre-send boundary. Replacement is honored fail-closed, never
 * silently: it must be a non-null, non-array object, keep the bootstrapped
 * `sessionId`, and carry a non-empty prompt array — prompt rewriting is
 * upstream-granted power, but entwurf cannot truthfully deliver to an ACP
 * session it did not open, and an emptied prompt would undo this rail's own
 * non-empty-prompt invariant; either refuses the turn before the wire.
 *
 * `options.onResponse` is an EXPLICIT LOCAL NON-HTTP EXEMPTION and is never
 * invoked anywhere on this rail: pi hard-types it as HTTP `{status, headers}`
 * (and the `after_provider_response` extension event re-emits exactly that), and
 * ACP's terminal result arrives only AFTER the session-update body was already
 * consumed — both the shape and the "before consuming its body" ordering are
 * unmappable, so any call would fabricate HTTP evidence that does not exist.
 * The absence is pinned behaviorally by check-acp-stream-hooks.
 */
async function applyProviderPayloadHook<T extends { sessionId: string }>(
	options: SimpleStreamOptions | undefined,
	params: T,
	model: Model<Api>,
): Promise<T> {
	const onPayload = options?.onPayload;
	if (!onPayload) return params;
	const replacement = await onPayload(params, model);
	if (replacement === undefined) return params;
	if (typeof replacement !== "object" || replacement === null || Array.isArray(replacement)) {
		throw new Error(
			"entwurf: before_provider_request returned a non-object replacement — the ACP prompt payload must stay a non-null, non-array object",
		);
	}
	if ((replacement as { sessionId?: unknown }).sessionId !== params.sessionId) {
		throw new Error(
			"entwurf: before_provider_request changed the ACP sessionId — entwurf cannot truthfully deliver to a session it did not bootstrap; prompt rewriting is allowed, session identity is not",
		);
	}
	const replacementPrompt = (replacement as { prompt?: unknown }).prompt;
	if (!Array.isArray(replacementPrompt) || replacementPrompt.length === 0) {
		throw new Error(
			"entwurf: before_provider_request returned a replacement without a non-empty prompt array — an empty ACP prompt cannot be sent",
		);
	}
	return replacement as T;
}

/**
 * streamSimple for the entwurf provider. Returns the event stream
 * synchronously and drives the ACP turn on a microtask.
 */
export function streamShellAcp(
	model: Model<Api>,
	context: Context,
	options?: SimpleStreamOptions,
): ReturnType<typeof createAssistantMessageEventStream> {
	return streamAcpTurn(model, context, options, defaultDeps());
}

/** The seam-aware turn driver. `streamShellAcp` calls this with the real deps. */
export function streamAcpTurn(
	model: Model<Api>,
	context: Context,
	options: SimpleStreamOptions | undefined,
	deps: AcpTurnDeps,
): ReturnType<typeof createAssistantMessageEventStream> {
	const stream = createAssistantMessageEventStream();
	// When THIS turn began. The idle gap that expires a prompt cache is the time
	// between turns, so it must be measured to a turn's START — measuring to its
	// seal would fold this turn's own duration into the gap and call a 58-minute
	// pause plus a 4-minute turn "62m idle", which crosses the 1h TTL in the
	// report while nothing crossed it in fact. pi's native detector uses message
	// timestamps for the same reason (read at pi-coding-agent
	// `dist/core/cache-stats.js:14-37`, `idleMs`).
	const turnStartedAtMs = Date.now();
	const state: AcpPiStreamState = createAcpStreamState(stream, {
		api: "entwurf",
		provider: "entwurf",
		model: model.id,
	});
	const opts = options as
		| ({ cwd?: string; signal?: AbortSignal; sessionId?: string } & SimpleStreamOptions)
		| undefined;
	const cwd = opts?.cwd ?? process.cwd();
	const signal = opts?.signal;

	stream.push({ type: "start", partial: state.output });

	// Per-turn event router → the CURRENT stream state. The retained connection's
	// callbacks delegate here; we install it per turn and clear it in finally.
	function makePromptHandler(session: BridgeSession): (event: AcpBridgeEvent) => void {
		return (event) => {
			if (event.type === "session_notification") {
				if (event.sessionId && session.acpSessionId && event.sessionId !== session.acpSessionId) return;
				applyAcpSessionUpdate(state, event.update);
			} else if (event.decision) {
				pushPermissionNotice(state, "permission request", event.decision);
			}
		};
	}

	/**
	 * Seal this turn's ACCOUNTING — the #93 authority boundary.
	 *
	 * Runs ONLY for a backend whose adapter declares `sealsTurnAccounting`. Flag
	 * absence means that backend's usage semantics were never measured, so nothing
	 * is sealed and its emitted usage is whatever the common mapper produced —
	 * unchanged, not guessed at.
	 *
	 * Two INDEPENDENT axes, because they arrive on different wires:
	 *
	 *   tokens  the turn aggregate, relayed from PromptResponse on `usage.acp`.
	 *   cost    an ADJACENT DIFF of the backend's own running session total, which
	 *           arrives on `usage_update` and is captured raw by the mapper.
	 *
	 * The diff is what makes the session sum reproduce the backend's own running
	 * total exactly — with no residue, which is what the gate measures. Read that
	 * exactness for what it is: agreement with the BACKEND'S CUMULATIVE ESTIMATE,
	 * never with an Anthropic invoice. The vendor calls `total_cost_usd` a
	 * "Cumulative estimated cost" and "An estimate, not a billing statement"
	 * (claude-agent-sdk `sdk.d.ts:4884`), and entwurf has measured no live
	 * comparison against a bill.
	 *
	 * We prefer that estimate anyway for a STRUCTURAL reason, not because it is
	 * more precise in general: it is computed UPSTREAM of a lossy flattening we
	 * cannot undo. The observed cache-writes are entirely 1h, ACP carries no 1h
	 * field, and pi prices a write with no `cacheWrite1h` at the 5m rate (read at
	 * pi-coding-agent `dist/bundle/chunks/bedrock-converse-stream.js`,
	 * `calculateCost`) — a local recompute measured $1.66 low on one live
	 * ledger. Nothing here calls calculateCost: any price table we could apply
	 * runs DOWNSTREAM of that flattening, so it would be a second, wronger
	 * source.
	 */
	function sealTurnUsage(adapter: AcpBackendAdapter, session: BridgeSession, promptResult: AcpPromptResponse): void {
		if (!adapter.sealsTurnAccounting) return;

		// --- the turn's ACCOUNTING aggregate, verbatim ------------------------
		// ACP reports one number set per turn and it is the SUM OVER THAT TURN'S API
		// ROUND TRIPS. It is carried on its OWN key, never on pi's four, because
		// those four mean ONE REQUEST's prompt shape to two readers that never go
		// through `calculateContextTokens` and so cannot be rescued by an honest
		// `totalTokens` (isContextOverflow, read at pi-ai
		// `dist/utils/overflow.js:132-145`; cache-stats.detectMiss, read at
		// pi-coding-agent `dist/core/cache-stats.js:14-37`). Projecting the
		// aggregate onto them compacted a live 223,516-token session on a 1,000,000
		// window (measured 2026-09-01).
		//
		// Nothing is computed here: these are the vendor's own four numbers, put
		// somewhere they cannot be mistaken for a per-request reading. pi stores an
		// assistant message as JSON and reads it back the same way (read at
		// pi-coding-agent `dist/core/session-manager.js:768-777` appendMessage,
		// `:98` parseSessionEntries), so a key pi does not know survives a resume.
		const aggregate = readTurnAccounting(promptResult);
		const mainLoop = readMainLoopAccounting(promptResult);
		if (aggregate) {
			(state.output.usage as unknown as { acp?: AcpTurnAccounting }).acp = aggregate;
		}

		// --- token axis: DELIBERATELY UNWRITTEN ------------------------------
		// The four token fields stay at their zero initialisation. ACP's only token
		// carrier is `PromptResponse.usage`, and that is the SUM OVER THIS TURN'S
		// API ROUND TRIPS — measured 2026-09-02 on one 21-round-trip turn whose
		// overlay rows summed to exactly the four numbers ACP reported
		// (cacheRead 4,185,084) while the context it occupied was 223,516.
		//
		// pi reads these four as ONE REQUEST's prompt shape, in two places that do
		// NOT go through `calculateContextTokens` and so cannot be rescued by the
		// honest `totalTokens` written below:
		//
		//   isContextOverflow  `input + cacheRead > contextWindow` (read at pi-ai
		//                      `dist/utils/overflow.js:132-145`). The aggregate made
		//                      that true at 223k of a 1M window and compacted a live
		//                      session — the defect this seal now refuses to feed.
		//   detectMiss         `input + cacheRead + cacheWrite` vs the previous
		//                      request (read at pi-coding-agent
		//                      `dist/core/cache-stats.js:14-37`). Under the aggregate
		//                      it invented two phantom misses and SILENCED the real
		//                      195,177-token one after a 401-minute idle gap.
		//
		// Writing zeros is not a placeholder for a better number we could compute:
		// the per-request partition is genuinely absent from the wire. The vendor
		// builds it in `lastAssistantUsage` and sends only its scalar sum (read at
		// claude-agent-acp 0.75.1 `dist/acp-agent.js:3853-3878`) — #96.
		//
		// But silence is NOT the resting state. A cache miss the operator never sees
		// is a false reading, not a modest one: a session can run for hours believing
		// its badge while a full prefix rewrite has already been paid for. So the
		// aggregate rides its own key above, and the bound below reports the rewrite.

		// --- context occupancy (NOT a turn total — see the field's note) -----
		// Refresh from THIS turn's notification when there was one, then assign the
		// session's value UNCONDITIONALLY. The assignment is not conditional on the
		// notification having been missing: on this path the seal — not the mapper —
		// is the authority for what pi reads as occupancy, and when a fresh value did
		// arrive the two agree by construction.
		//
		// Why the field must be right rather than merely non-zero: pi's auto-compaction
		// takes `calculateContextTokens(message.usage)` at face value and falls back to
		// its own estimate ONLY when the message errored or that value is exactly 0
		// (read at pi-coding-agent `dist/core/agent-session.js:1696-1697`). A turn
		// aggregate written here would be non-zero and therefore never corrected — the
		// session would read as nearly empty all the way to an overflow.
		const priorOccupancy = session.contextOccupancyTokens;
		const priorIoSum = session.priorTurnInputOutputSum;
		const priorSealedAtMs = session.priorTurnSealedAtMs;

		const occupancy = state.observedContextOccupancyTokens;
		if (typeof occupancy === "number") session.contextOccupancyTokens = occupancy;
		if (typeof session.contextOccupancyTokens === "number") {
			state.output.usage.totalTokens = session.contextOccupancyTokens;
		}

		// --- cache-miss bound (the rewrite the operator must not miss) -------
		// Both quantities below are PROVEN INTERVALS derived from numbers already in
		// hand, not estimates. See `priorTurnInputOutputSum` for the identity and its
		// telescoping. Only the LAST request's input+output is unknown at turn scope,
		// and each turn's own sums bound it:
		//
		//   cacheRead_first ≤ used_end − ΣcacheWrite                     (upper)
		//   expected        ≥ used_prev − (Σinput' + Σoutput')           (lower)
		//   miss            ≥ expected_lower − cacheRead_first_upper
		//
		// The interval is proven only while the within-turn recurrence holds, and that
		// recurrence is an OBSERVED property of Claude Code's breakpoint placement
		// (measured 2026-09-02 corpus-wide: 2,398 of 2,410 adjacent pairs, 99.50%; see
		// `priorTurnInputOutputSum` for the full count and the break characterisation),
		// not a guarantee. If it breaks mid-turn — a 1h TTL expiring
		// between round trips, or the child compacting itself — `used_end − ΣcacheWrite`
		// goes negative and the `max(0, …)` below assumes cacheRead_first = 0. The
		// notice is still TRUE (a rewrite did happen) but its N is then a floor of a
		// weaker kind, not a telescoped bound. #96 carries that limit.
		//
		// A negative or small bound proves nothing was re-billed beyond breakpoint
		// granularity, so nothing is said. The floor is the TOKEN half of pi's own
		// native cache-miss display policy, which suppresses a notice only when the
		// miss is under 20,000 tokens AND under $0.10 (read at pi-coding-agent
		// `dist/modes/interactive/interactive-mode.js:3130`). The ACP rail borrows
		// that familiar token threshold alone and claims no part of the cost half:
		// this bound is a token interval, and pricing it locally is the very
		// downstream reprice the cost axis above refuses.
		// The re-billed size can never exceed what this turn's MAIN LOOP actually
		// WROTE: a re-billed prefix is paid for as cache creation. Clamping to
		// `mainLoop.cacheWrite` (not the wide aggregate) is what keeps the notice
		// a statement about money that changed hands on the prefix rather than
		// about the recurrence holding, or about an internal compaction write.
		//
		// Without it a context SHRINK reads as a giant miss. Worked counterexample
		// (gpt-5.6-sol, 2026-09-02): prior occupancy 200,000, prior IO 1,000, this
		// turn occupancy 20,000 with cacheWrite 1,000 — organic compaction, nothing
		// re-billed — yields 200,000 − 1,000 − 19,000 = 180,000 and would announce
		// "cache miss ≥180k" over a turn that wrote 1,000 tokens. The clamp answers
		// 1,000, which is under the floor, so nothing is said. On the real incident
		// the clamp does not bind: 191,971 ≤ cacheWrite 221,084.
		//
		// Both prior marks are read from ONE turn and written from ONE turn. Mixing
		// an older occupancy with a newer IO sum puts two turns in one equation and
		// can skew the bound HIGH, so the update below is all-or-nothing.
		//
		// The same all-or-nothing applies to SCOPE. Occupancy is main-context;
		// the recurrence is a main-loop identity. `aggregate.cacheWrite` is the
		// WIDE accounting figure (Task subagents, sidechains, internal compaction).
		// A large unrelated wide write shrinks `max(0, occupancy − cacheWrite)`
		// (less is subtracted) AND raises the `min(…, cacheWrite)` ceiling — both
		// paths push the bound UP, so a warm main prefix can announce a miss and
		// attach this turn's all-inclusive dollar figure to it. The IO terms
		// therefore come from `mainLoop`, never from `aggregate`.
		const derivable =
			mainLoop !== undefined &&
			typeof occupancy === "number" &&
			typeof priorOccupancy === "number" &&
			typeof priorIoSum === "number";
		const cacheWriteForBound = mainLoop !== undefined ? mainLoop.cacheWrite : 0;
		const rawBound = derivable
			? (priorOccupancy as number) - (priorIoSum as number) - Math.max(0, (occupancy as number) - cacheWriteForBound)
			: undefined;
		const missLowerBound = rawBound === undefined ? undefined : Math.min(rawBound, cacheWriteForBound);

		if (mainLoop && typeof occupancy === "number") {
			session.priorTurnInputOutputSum = mainLoop.input + mainLoop.output;
			session.priorTurnSealedAtMs = Date.now();
		}

		// --- cost axis ------------------------------------------------------
		// ALWAYS assigned on this path, including the 0 cases: the mapper may have
		// written the running cumulative into this field, and leaving it would put a
		// session total on a dashboard that sums per-turn costs — the whole defect.
		const observed = state.observedSessionCostUsd;
		let turnCostUsd: number | undefined;
		if (typeof observed !== "number") {
			// No cumulative arrived this turn. HOLD the baseline: this turn's real
			// amount is still inside the backend's running total and the next
			// adjacent diff absorbs it. Attributed to the wrong turn, exact in the
			// session sum. Zeroing the baseline here would double-count it instead.
			state.output.usage.cost.total = 0;
		} else {
			const diff = observed - (session.sdkCumulativeCostUsd ?? 0);
			if (diff < 0) {
				// The backend's running total went BACKWARDS. TWO receipts, and the gap
				// between them is exactly why the notice below names a MECHANISM and
				// never a cause: claude-agent-acp's `conversation_reset` handler only
				// switches the SDK to a fresh conversation and touches no cost at all
				// (read at 0.75.1 `dist/acp-agent.js:4282-4289`), while claude-agent-sdk
				// separately documents that "a mid-session /clear resets the running
				// total" (read at 0.3.257 `sdk.d.ts:4884`). A reset therefore PLAUSIBLY
				// explains a backwards total, but nothing here has MEASURED that it did,
				// and asserting the cause would be the same unmeasured claim this lane
				// exists to end.
				// Rebaseline and attribute 0 — but SAY SO. Silently absorbing it would
				// hide the one observation that can settle what a reset does to the
				// total, which is precisely the "no silent misaccounting" this lane owes.
				const detail = `${(session.sdkCumulativeCostUsd ?? 0).toFixed(6)} → ${observed.toFixed(6)} USD`;
				session.sdkCumulativeCostUsd = observed;
				state.output.usage.cost.total = 0;
				// Kept under the notice fragment cap (80) so the two numbers survive
				// verbatim — a truncated diagnostic is not evidence.
				pushAcpLifecycleNotice(state, `cost baseline reset (${detail}) — this turn attributed $0`);
				console.error(
					`entwurf: ACP backend reported a DECREASING session cost (${detail}). Rebaselined; this turn is ` +
						`attributed $0. The cause is NOT measured here. The one documented mechanism is a mid-session ` +
						`/clear, which claude-agent-sdk (sdk.d.ts:4884) says resets the running total; the adapter's ` +
						`conversation_reset event is NOT it — that handler switches conversation and touches no cost. ` +
						`The session total from here on is measured against the new baseline.`,
				);
			} else {
				session.sdkCumulativeCostUsd = observed;
				state.output.usage.cost.total = diff;
				turnCostUsd = diff;
			}
		}

		// --- report the rewrite ----------------------------------------------
		// Said LAST so it can quote what this turn actually cost. The cost is the
		// SDK's own adjacent diff, never a local repricing.
		if (typeof missLowerBound === "number" && missLowerBound >= CACHE_MISS_NOTICE_FLOOR_TOKENS) {
			// Only when there is an idle gap worth naming. A sub-minute one explains
			// nothing and "after 0m idle" reads as noise, so the clause is dropped —
			// the re-billed size and the cost still stand on their own.
			const idleMinutes =
				typeof priorSealedAtMs === "number" ? Math.round((turnStartedAtMs - priorSealedAtMs) / 60_000) : 0;
			const idle = idleMinutes >= 1 ? ` after ${idleMinutes}m idle` : "";
			const paid = typeof turnCostUsd === "number" ? ` — this turn $${turnCostUsd.toFixed(2)}` : "";
			pushAcpLifecycleNotice(state, `cache miss ≥${formatTokenCount(missLowerBound)} re-billed${idle}${paid}`);
		}
	}

	/**
	 * Seal the turn from the ACP prompt result. "Success" here means the RPC
	 * returned, not that the turn ended well — a returned `refusal` /
	 * `max_turn_requests` / unknown / absent reason is sealed as an error event,
	 * never a `done`. `rawStopReason` carries the wire value out either way.
	 */
	function finishSuccess(adapter: AcpBackendAdapter, session: BridgeSession, promptResult: AcpPromptResponse): void {
		sealTurnUsage(adapter, session, promptResult);
		finalizeAcpStreamState(state);
		const verdict = mapPromptStopReason(promptResult?.stopReason);
		if (verdict.rawStopReason !== undefined) state.output.rawStopReason = verdict.rawStopReason;
		if (signal?.aborted || verdict.stopReason === "aborted") {
			state.output.stopReason = "aborted";
			stream.push({ type: "error", reason: "aborted", error: state.output });
		} else if (verdict.stopReason === "error") {
			state.output.stopReason = "error";
			state.output.errorMessage = verdict.errorMessage;
			stream.push({ type: "error", reason: "error", error: state.output });
		} else {
			state.output.stopReason = verdict.stopReason;
			stream.push({
				type: "done",
				reason: verdict.stopReason === "length" ? "length" : "stop",
				message: state.output,
			});
		}
		stream.end();
	}

	function finishError(
		err: unknown,
		aborted: boolean,
		stderrTail?: string[],
		lifecycle?: string,
		launchObservation?: AcpLaunchObservation,
	): void {
		finalizeAcpStreamState(state);
		state.output.stopReason = aborted ? "aborted" : "error";
		const base = err instanceof Error ? err.message : String(err);
		// The FIRST failure stays first and verbatim (it is what the backend
		// actually said); the lifecycle line is added, never substituted, so a
		// reader can still match the transport's own text.
		const withLifecycle = lifecycle ? `${base}\n${lifecycle}` : base;
		// Its OWN line, above the vendor tail: an entwurf-owned observation must not
		// have to be recovered by reading vendor prose.
		const observed = launchSignalLine(launchObservation);
		const diagnosed = observed ? `${withLifecycle}\n${observed}` : withLifecycle;
		const tail = (stderrTail ?? []).join("").trim().slice(-1_000);
		const full = tail ? `${diagnosed}\n--- backend stderr (tail) ---\n${tail}` : diagnosed;
		// A-c: a real failure (not an abort) that looks like a context-window
		// overflow gets an actionable hint appended, so "API Error" stops hiding
		// the turn-scoped full-transcript-replay cause.
		const hint = aborted ? undefined : actionableAcpBackendHint(full);
		state.output.errorMessage = hint ? `${full}\n\n${hint}` : full;
		stream.push({ type: "error", reason: aborted ? "aborted" : "error", error: state.output });
		stream.end();
	}

	queueMicrotask(async () => {
		// Operator provider config (S2g) — resolve FIRST. A config the bridge
		// cannot honor (bad mcpServers / skillPlugins / appendSystemPrompt:true /
		// strictMcpConfig:false) fails loud into the stream before any spawn. This
		// is the baseline fix: the operator's entwurfProvider.{mcpServers,
		// skillPlugins,tools,…} now actually reach the session.
		// Backend adapter — resolve ONCE at turn entry (GPT §9 / Step B). The modelId
		// prefix routes to the owning adapter; an unknown or colliding id fails loud.
		let adapter: AcpBackendAdapter;
		let nativeModelId: string;
		try {
			({ adapter, nativeModelId } = resolveAcpBackendAdapter(model.id));
		} catch (err) {
			finishError(err, false);
			return;
		}
		let config: ResolvedAcpConfig;
		try {
			config = deps.loadConfig(cwd, model.id, adapter);
		} catch (err) {
			finishError(err, false);
			return;
		}
		// settings.backend is a DIAGNOSTIC guard, never a router. The model id already
		// chose the adapter (above); if the operator ALSO declared a backend it must
		// agree, else fail loud — a mismatch means the settings and the requested model
		// disagree about which backend runs, and silently trusting the model id would
		// hide an operator typo. Routing authority stays single (the model id).
		if (config.backend !== undefined && config.backend !== adapter.backend) {
			finishError(
				new Error(
					`entwurf: entwurfProvider.backend "${config.backend}" does not match the backend that owns model ` +
						`"${model.id}" (${adapter.backend}) — the model id is the routing authority; fix or remove the backend field`,
				),
				false,
			);
			return;
		}
		const serverNames = mcpServerNames(config);
		// S2g: apply the operator's tool/permission notice preference to THIS turn's
		// stream. Display-only rendering config (not session-compat), so it is set on
		// the stream state and deliberately kept OUT of bridgeConfigSignature. The S2f
		// lifecycle notices ignore this flag (always visible) — only the verbose
		// [tool:*] / [permission:*] stream is suppressed when false.
		state.showToolNotifications = config.showToolNotifications;

		// Tool-surface truthfulness preflight (S2b assertExcludeToolsHonored) —
		// BEFORE any spawn or session lookup. If pi excluded a built-in the Claude
		// child will still expose (declared != actual), fail fast into the stream
		// rather than lie to the model. Uses the RESOLVED tool surface (S2g) so an
		// operator-narrowed `tools` is what the truthfulness check honors.
		try {
			const activeToolNames = context.tools?.map((t) => t.name) ?? [...PI_BUILTIN_BACKED_TOOLS];
			assertExcludeToolsHonored(activeToolNames, { backend: adapter.backend, tools: config.tools });
		} catch (err) {
			finishError(err, false);
			return;
		}

		const policy = deps.lifecyclePolicy();
		const sessionKey = resolveSessionKey(opts, cwd);
		// Billing/memory carrier (S2d-1c): SHORT operator-authored system-prompt
		// additions. The shipped default is NON-empty → tiny string carrier →
		// claude_code preset replacement, which strips auto-memory. The SAME rendered
		// string feeds BOTH the config signature (appendSystemPrompt) and
		// _meta.systemPrompt (in runNewTurn), so a carrier change invalidates reuse;
		// loadEngraving is pure (no clock/random/env) so the signature stays a
		// per-(model,template) constant and does NOT rebuild every turn (NEXT
		// §S2-scout 핀1 / oracle C, GPT c32a6c8 ②). null → "" is the explicit
		// operator opt-out branch. mcpServerNames feed the carrier so
		// `{{mcp_servers}}` lists the real set. If the shipped default carrier is
		// missing/empty, loadEngraving throws (trust lever off); surface that as a
		// stream error instead of an unhandled microtask failure.
		let engraving: string | null;
		try {
			engraving = adapter.loadCarrier({ mcpServerNames: serverNames, config });
		} catch (err) {
			finishError(err, false);
			return;
		}
		// S2g: the signature folds the FULL resolved config (mcpServersHash + tool
		// surface + skillPlugins + flags) so any operator config change invalidates
		// a reused session; the per-session envelope is excluded (runtime, not config).
		const configSig = bridgeConfigSignature({
			backend: adapter.backend,
			modelId: model.id,
			nativeModelId,
			appendSystemPrompt: engraving ?? "",
			mcpServersHash: config.mcpServersHash,
			settingSources: [...config.settingSources],
			strictMcpConfig: config.strictMcpConfig,
			tools: [...config.tools],
			skillPlugins: [...config.skillPlugins],
			permissionAllow: [...config.permissionAllow],
			disallowedTools: [...config.disallowedTools],
			extra: adapter.configSignatureFields(config.adapterSettings),
		});
		const ctxSigs = contextMessageSignatures(context);
		const params: BootstrapParams = {
			cwd,
			modelId: model.id,
			bridgeConfigSignature: configSig,
			contextMessageSignatures: ctxSigs,
			lifecyclePolicy: policy,
		};

		const existing = bridgeSessions.get(sessionKey);

		// Concurrent prompt on the same sessionKey → fail-loud (first cut: no
		// queue). Covers BOTH a retained busy session AND an in-flight FIRST turn
		// (a NEW turn is not in the map yet — inFlightKeys). Checked BEFORE we
		// claim/spawn/set any handler, so nothing to unwind (GPT blocker 1).
		if (existing?.busy || inFlightKeys.has(sessionKey)) {
			finishError(new Error(`entwurf session ${sessionKey} is busy with another prompt`), false);
			return;
		}

		const existingFacts: ExistingSession | undefined = existing
			? {
					cwd: existing.cwd,
					modelId: existing.modelId,
					bridgeConfigSignature: existing.bridgeConfigSignature,
					contextMessageSignatures: existing.contextMessageSignatures,
					alive: existing.alive,
				}
			: undefined;

		let decision: BootstrapDecision;
		try {
			// 1b-2b: persisted resume/load is OFF — no persisted record and no
			// resume/load capability passed, so decideBootstrap returns only
			// "new" or "reuse". (Persisted resume/load is the 1b-2c lane.)
			decision = decideBootstrap(params, { existing: existingFacts });
		} catch (err) {
			// Model lock (live alive child, different model): surface as a stream
			// error. Do NOT close the live child or drop it from the map — a
			// mismatch means "not reusable for THIS turn", not "dead" (GPT ③).
			finishError(err, false);
			return;
		}

		// A "new" decision WITH an existing session means we are ABANDONING that
		// session (incompatible drift / stale-dead) — the model-lock throw already
		// returned above, so this is never a "leave it alone" case. Close the old
		// connection + child so it is not orphaned in retainedChildren (GPT blocker 2).
		if (decision.path === "new" && existing) {
			existing.alive = false;
			existing.retiring = true;
			if (bridgeSessions.get(sessionKey) === existing) bridgeSessions.delete(sessionKey);
			retainedChildren.delete(existing.child);
			existing.connection.close?.();
			teardownChild(existing.child);
		}

		// Claim the key for the whole turn — atomic with the checks above (no await
		// in between), so a concurrent first turn for the same key sees it in flight
		// and fails loud (GPT blocker 1).
		inFlightKeys.add(sessionKey);
		try {
			if (decision.path === "reuse" && existing) {
				await runReuseTurn(existing, ctxSigs, adapter);
			} else {
				await runNewTurn(params, ctxSigs, engraving, config, adapter, nativeModelId);
			}
		} finally {
			inFlightKeys.delete(sessionKey);
		}
	});

	// --- new session: spawn → initialize → newSession → setSessionConfigOption(model) → full transcript
	async function runNewTurn(
		params: BootstrapParams,
		ctxSigs: string[],
		engraving: string | null,
		config: ResolvedAcpConfig,
		adapter: AcpBackendAdapter,
		nativeModelId: string,
	): Promise<void> {
		let child: AcpChildLike | undefined;
		let session: BridgeSession | undefined;
		let onAbort: (() => void) | undefined;
		/** Which phase a failure belongs to — flipped once the prompt is on the wire. */
		let phase: "pre-prompt" | "prompt" = "pre-prompt";
		const stderrTail: string[] = [];
		// Session-scoped alongside the tail — see the field's note on the session type.
		const launchObservation: AcpLaunchObservation = {};
		const sessionKey = resolveSessionKey(opts, cwd);
		try {
			if (signal?.aborted) throw new Error("aborted before launch");

			// A backend session that died BETWEEN turns is announced here, before
			// the bootstrap notice — otherwise this turn looks like an ordinary
			// cold start and the operator never learns that the session they were
			// talking to ended. Announced once (read-and-clear); the turn continues
			// normally, since opening a fresh child for a NEW user turn is not a
			// replay of anything.
			const priorEnd = takeUnreportedChildEnd(sessionKey);
			if (priorEnd) {
				pushAcpLifecycleNotice(
					state,
					`previous ${adapter.backend} session ended between turns (${describeChildEnd(priorEnd)}) — opening a new one`,
				);
			}
			// S2f visibility: surface the otherwise-silent bootstrap so a slow
			// overlay/spawn/init does not read as a hang. Display-only (marked).
			pushAcpLifecycleNotice(state, `preparing ${adapter.backend} session`);
			// Overlay ordering (rail “Adapter contract”): materialize the overlay first, then spawn with launchEnvDefaults
			// + overlay.envOverrides merged over process.env (defaultDeps spawnChild).
			// sessionKey is the AUTHORITATIVE per-session identity (resolveSessionKey:
			// opts.sessionId → PI_SESSION_ID → cwd) — a session-scoped overlay must
			// scope on it, so it rides the params explicitly and the adapter never
			// re-derives a weaker key from ambient env (P0-1).
			const overlay = adapter.ensureOverlay({ cwd, modelId: model.id, nativeModelId, config, sessionKey });
			const launch = adapter.resolveLaunch({ cwd, modelId: model.id, nativeModelId, config });
			child = deps.spawnChild(launch, cwd, { ...adapter.launchEnvDefaults(), ...overlay.envOverrides });
			const spawned = child;

			// Drain stderr (an unconsumed pipe can backpressure-deadlock a long turn).
			// The launcher's own control frames are consumed here and kept OUT of the
			// tail: the tail is vendor evidence, the observation is an entwurf fact,
			// and mixing the two is the overloading #72 was made of.
			const consumeStderr = makeLaunchFrameFilter(launchObservation, (text) => {
				stderrTail.push(text);
				if (stderrTail.length > 50) stderrTail.shift();
			});
			spawned.stderr.on("data", (c: Buffer) => consumeStderr.write(c.toString()));
			// `close` rather than `end`: it covers the destroy path our own teardown
			// takes, and on the EOF-first death it lands inside the post-mortem
			// settle window, so the flushed fragment is in the tail before we seal.
			spawned.stderr.once?.("close", () => consumeStderr.flush());

			// Abort during BOOTSTRAP (spawn → initialize → newSession → set-model):
			// there is no prompt turn for the agent to cancel yet, so the child is
			// simply torn down. This listener is handed off before the prompt —
			// awaitAcpPromptTurn installs the protocol-cancel-first one for that
			// window, and two live listeners would race SIGTERM against the cancel.
			if (signal) {
				onAbort = () => killChildGroup(spawned, "SIGTERM");
				signal.addEventListener("abort", onAbort, { once: true });
			}

			// Mutable-routing callbacks — they read `session` (assigned just below)
			// and delegate to its per-turn activePromptHandler. NEVER close over a
			// turn's stream state directly (CRITICAL — see file header).
			const handlers: AcpClientHandlers = {
				sessionUpdate: async (n) => {
					session?.activePromptHandler?.({
						type: "session_notification",
						update: n?.update,
						sessionId: n?.sessionId,
					});
				},
				requestPermission: async (req) => {
					const response = resolvePermissionResponse(req);
					const decision = response.outcome.outcome === "selected" ? "approved" : "cancelled";
					session?.activePromptHandler?.({ type: "permission_request", decision });
					return response;
				},
				readTextFile: async (req) => ({ content: readFileSync(req.path, "utf8") }),
				writeTextFile: async (): Promise<never> => {
					throw new Error("Client-side writeTextFile is not supported in entwurf ACP mode.");
				},
			};
			const connection = deps.createConnection(spawned, handlers);

			session = {
				key: sessionKey,
				cwd,
				modelId: model.id,
				child: spawned,
				connection,
				acpSessionId: "",
				bridgeConfigSignature: params.bridgeConfigSignature,
				contextMessageSignatures: ctxSigs,
				alive: true,
				busy: true,
				activePromptHandler: undefined,
				// SAME array the stderr drain above pushes into: the buffer outlives
				// this turn with the session, so a later reuse turn can still report
				// the child's dying words.
				stderrTail,
				// SAME object the frame filter writes into, for the same reason.
				launchObservation,
				// Armed at spawn, before ANY turn can fail on this child — the latch
				// must already exist when the `exit` listener below can fire.
				childEnd: makeChildEndLatch(),
			};
			const sess = session;
			spawned.once("exit", (...args: unknown[]) =>
				onChildGone(sess, { code: (args[0] as number | null) ?? null, signal: (args[1] as NodeJS.Signals) ?? null }),
			);
			spawned.once("error", () => onChildGone(sess));

			await withTimeout(
				"initialize",
				connection.initialize({
					protocolVersion: PROTOCOL_VERSION,
					clientCapabilities: {},
					clientInfo: { name: "entwurf", version: "s2d" },
				}),
				INITIALIZE_TIMEOUT_MS,
			);

			// Tool-narrowed session meta (S2b) + the billing carrier (S2d-1c). The
			// carrier is the SAME rendered engraving folded into configSig above;
			// when null, buildClaudeSessionMeta omits the _meta.systemPrompt key
			// entirely so a carrier-absent session is byte-identical to 1b-2b.
			// S2g: the RESOLVED operator config drives the session meta (tools /
			// permission / disallowed / settingSources / strictMcpConfig / skillPlugins)
			// instead of the old hardcoded minimal surface.
			const sessionMeta = adapter.buildSessionMeta({ modelId: model.id, nativeModelId, config }, engraving);
			// Envelope-enrich the normalized servers at spawn time (PI_SESSION_ID/
			// PI_AGENT_ID into entwurf-bridge) — runtime wiring, applied AFTER the
			// config signature was taken so a new session id never forces a rebuild.
			const wireMcpServers = enrichMcpServersWithEnvelope(config.mcpServers, {
				modelId: model.id,
				piSessionId: process.env.PI_SESSION_ID?.trim() || undefined,
			});
			// Carrier-less shape (rail “Adapter contract”): omit the `_meta` KEY entirely for a carrier-less backend
			// (sessionMeta === undefined), not `_meta: undefined`.
			const newSessionArgs =
				sessionMeta === undefined
					? { cwd, mcpServers: wireMcpServers }
					: { cwd, mcpServers: wireMcpServers, _meta: sessionMeta };
			const created = await withTimeout("newSession", connection.newSession(newSessionArgs), NEW_SESSION_TIMEOUT_MS);
			const acpSessionId = created?.sessionId;
			if (!acpSessionId) throw new Error("newSession returned no sessionId");
			session.acpSessionId = acpSessionId;

			// Enforce the requested model — a silent default would lie about which
			// model answered. pi 0.50/sdk 0.29: model selection moved from the removed
			// unstable_setSessionModel to setSessionConfigOption({configId:"model"}).
			// The agent resolves the value (full id or alias) to a canonical model id
			// and routes it through query.setModel.
			await withTimeout(
				"enforceModel",
				adapter.enforceModel({ connection, acpSessionId, modelId: model.id, nativeModelId }),
				SET_MODEL_TIMEOUT_MS,
			);

			// S2f visibility: the session is live and model-locked — the next gap is
			// the prompt round-trip to the first token.
			pushAcpLifecycleNotice(state, `session ready model=${model.id}`);

			session.activePromptHandler = makePromptHandler(session);
			// new session holds NO history → the full transcript is the only carrier.
			const basePrompt = buildAcpPrompt(context, "new");
			if (basePrompt.length === 0) throw new Error("empty pi context — nothing to prompt");
			// S2d-1c: prepend the rich first-user augment (bridge identity + ~/AGENTS.md
			// + cwd/AGENTS.md + pi base + tool surface) on the WIRE only — never into
			// the pi Context, so it stays out of contextMessageSignatures (NEXT §S2d
			// gate ②). `new`-only → reuse turns stay clean (once-only). Entwurf-spawned
			// prompts that already carry cwd/AGENTS.md get that one section de-duped.
			const prompt = prependNewPromptAugment(basePrompt, {
				backend: adapter.backend,
				cwd,
				mcpServerNames: mcpServerNames(config),
				emacsAgentSocket: process.env.PI_EMACS_AGENT_SOCKET?.trim() || undefined,
			});

			// S2f visibility: about to send — say "sending" (not "sent") because the
			// prompt could still sync-reject before the wire write; the next visible
			// event after this is the backend's own first token / tool notice.
			pushAcpLifecycleNotice(state, "sending prompt");
			// #63: the pi streamSimple payload hook sees the EXACT wire params and may
			// replace them (fail-closed integrity inside the helper). It runs while the
			// bootstrap abort listener is still armed; the recheck below keeps an abort
			// raised during a slow handler ahead of the wire write.
			const wireParams = await applyProviderPayloadHook(options, { sessionId: acpSessionId, prompt }, model);
			if (signal?.aborted) throw new Error("aborted during payload hook");
			// Hand the abort window over to the prompt driver: from here on an abort
			// is a protocol `session/cancel` first, teardown only after the grace.
			if (signal && onAbort) {
				signal.removeEventListener("abort", onAbort);
				onAbort = undefined;
			}
			// From here the prompt is on the wire: a transport closure now is a
			// PROMPT-phase failure, and the catch says so.
			phase = "prompt";
			const promptResult = await awaitAcpPromptTurn(session, wireParams, {
				signal,
				graceMs: deps.abortGraceMs ?? ABORT_CANCEL_GRACE_MS,
			});

			session.activePromptHandler = undefined;
			session.busy = false;

			// Retain ONLY a long-lived process-scoped session that survived the turn
			// alive and un-aborted. A turn-scoped one-shot (and any aborted/dead
			// turn) tears down so its stdio handle cannot pin pi's exit (S2c hang).
			const retain = params.lifecyclePolicy === "process-scoped" && !signal?.aborted && session.alive;

			// DISCOVERABILITY BEFORE THE SEAL. `finishSuccess` ends the stream, and
			// ending the stream is what releases the caller — which may start the next
			// turn on that event. A completed process-scoped session that is not yet in
			// the map would send that turn down the NEW path: a second child, and with
			// it a FRESH cost baseline, so a long session's accounting would silently
			// reset at a turn boundary (#93).
			//
			// Two things make that window empty today — nothing here awaits, and the
			// turn's in-flight claim is not released until after this returns — but both
			// are invariants of surrounding code rather than of this ordering, and
			// neither is visible from this line. Registering first makes the guarantee
			// local: the session is discoverable before anything can act on the seal,
			// whatever the code around it later does.
			if (retain) {
				bridgeSessions.set(sessionKey, session);
				retainedChildren.add(spawned);
				registerGlobalCleanup();
				// unref so the retained stdio cannot pin pi's exit at resident
				// shutdown — reuse is unaffected (unref ≠ destroy). GPT amber.
				unrefRetainedChild(spawned);
			}

			finishSuccess(adapter, session, promptResult);

			if (retain) {
				// AFTER the seal, deliberately: persisting is bookkeeping about a turn
				// that already answered, so a failed record write must not convert an
				// answered turn into an error turn. If it throws, the catch below still
				// un-registers this session and tears its child down — the same cleanup
				// a sealing exception gets.
				persistRecord(session, deps);
			} else {
				session.retiring = true;
				connection.close?.();
				teardownChild(spawned);
			}
		} catch (err) {
			const aborted = Boolean(signal?.aborted);
			if (session) {
				session.activePromptHandler = undefined;
				session.busy = false;
				if (bridgeSessions.get(sessionKey) === session) bridgeSessions.delete(sessionKey);
			}
			// ORDER IS THE CONTRACT (#72): natural settle → seal → teardown.
			// The bounded wait for the child's own exit status runs BEFORE we signal
			// anything, so what we report is how the child actually ended and not our
			// own SIGTERM; the tail collected by then is sealed before our cleanup
			// touches the stderr pipe.
			const lifecycle = await diagnoseTransportClosure({ err, session, phase, aborted });
			finishError(
				err,
				aborted,
				session?.stderrTail ?? stderrTail,
				lifecycle,
				session?.launchObservation ?? launchObservation,
			);
			// error/abort → drop the (uncertain) session and close its child; an
			// uncertain connection must never be reused (GPT ④).
			if (child) {
				if (session) session.retiring = true;
				retainedChildren.delete(child);
				session?.connection.close?.(err);
				teardownChild(child);
			}
		} finally {
			if (signal && onAbort) signal.removeEventListener("abort", onAbort);
		}
	}

	// --- reuse: send only the latest user delta to the live ACP session
	async function runReuseTurn(session: BridgeSession, ctxSigs: string[], adapter: AcpBackendAdapter): Promise<void> {
		/** Same phase discipline as a new turn — reuse just has no bootstrap to lose. */
		let phase: "pre-prompt" | "prompt" = "pre-prompt";
		try {
			if (signal?.aborted) throw new Error("aborted before prompt");

			// S2f visibility: reuse skips spawn/init entirely — say so, otherwise a
			// resident turn looks identical to a cold start that stalled.
			pushAcpLifecycleNotice(state, "reusing live session");
			session.busy = true;
			session.activePromptHandler = makePromptHandler(session);

			// The live ACP session already remembers the prior turns → send only the
			// latest user delta (re-sending the transcript would duplicate history).
			const prompt = buildAcpPrompt(context, "reuse");
			if (prompt.length === 0) throw new Error("empty delta — a reuse turn has no new user message");

			// S2f visibility: about to send the delta to the resident child.
			pushAcpLifecycleNotice(state, "sending prompt");
			// #63: same hook boundary as a new turn — the reuse delta is the wire
			// params here. The recheck keeps an abort raised during a slow handler
			// ahead of the wire write; the prompt driver then owns the abort surface.
			const wireParams = await applyProviderPayloadHook(options, { sessionId: session.acpSessionId, prompt }, model);
			if (signal?.aborted) throw new Error("aborted during payload hook");
			phase = "prompt";
			const promptResult = await awaitAcpPromptTurn(session, wireParams, {
				signal,
				graceMs: deps.abortGraceMs ?? ABORT_CANCEL_GRACE_MS,
			});

			session.activePromptHandler = undefined;
			session.busy = false;
			// Advance the stored history to THIS call's context so the NEXT turn's
			// prefix-compat check sees the full prior history (GPT ④: store the
			// ctxSigs from the START of this call, only after the turn succeeds).
			session.contextMessageSignatures = ctxSigs;
			finishSuccess(adapter, session, promptResult);
			persistRecord(session, deps);
		} catch (err) {
			const aborted = Boolean(signal?.aborted);
			session.activePromptHandler = undefined;
			session.busy = false;
			if (bridgeSessions.get(session.key) === session) bridgeSessions.delete(session.key);
			// The SAME diagnostics a new turn reports, in the SAME order (#72):
			// natural settle → seal → teardown. This is the path the field sample
			// took — a retained child that died after its tool phase — so the
			// ordering matters most here: teardown first would have overwritten the
			// child's own exit status with our SIGTERM.
			const lifecycle = await diagnoseTransportClosure({ err, session, phase, aborted });
			// Without the session-scoped tail a mid-turn child death on a resident
			// session surfaced as a bare "ACP connection closed" with nothing to read
			// it by.
			finishError(err, aborted, session.stderrTail, lifecycle, session.launchObservation);
			// error/abort on a reused session → drop it and close the child (GPT ④).
			session.retiring = true;
			retainedChildren.delete(session.child);
			session.connection.close?.(err);
			teardownChild(session.child);
		}
	}

	return stream;
}
