// Deterministic gate for the ACP USAGE ACCOUNTING contract (#93).
//
// WHAT THIS EXISTS TO STOP. A long-lived Claude ACP session's dashboard lied by
// 10-18x, measured on three independent live ledgers (oracle 18x / oracle 10.5x
// / thinkpad 14.4x, #93). Two defects produced that one number:
//
//   1. `PromptResponse.usage` — the only per-turn token carrier on the wire, and
//      a ROUND-TRIP AGGREGATE rather than a per-request partition —
//      was erased at the type boundary, so every ACP assistant message reported
//      input/output/cacheRead/cacheWrite as 0. The cache-efficiency badge the
//      operator wanted could not be computed at all: its inputs were zeroes.
//   2. The one number that DID survive, `usage_update.cost.amount`, is the
//      backend's RUNNING SESSION TOTAL. It was assigned to a per-TURN field, and
//      pi's footer sums per-turn costs. Summing a monotonically increasing series
//      is how $24.261 was displayed as $444.370.
//
// The contract now:
//
//   tokens    are NOT written at all. ACP's only carrier is a per-turn round-trip
//             AGGREGATE and pi's four fields mean ONE REQUEST's prompt shape;
//             projecting one onto the other fired a false overflow (#93, measured
//             2026-09-02). Silence until the wire carries a per-request partition.
//   cost      is an ADJACENT DIFF of the backend's own running total, held on the
//             BridgeSession. A missing total HOLDS the baseline (the amount lands
//             in the next diff — misattributed by turn, exact by session). A
//             DECREASING total rebaselines, attributes $0, and SAYS SO.
//   totalTokens is CONTEXT OCCUPANCY, not a turn total, and is never overwritten
//             with the turn aggregate — pi reads that field as the context gauge.
//   a backend with no measured semantics (no sealsTurnAccounting) is sealed NOT AT
//             ALL: cortex's emitted usage must be byte-identical to pre-#93.
//
// ORACLES, each independent of the subject:
//   - the cost sum: THIS FILE constructs the cumulative series and asserts the
//     emitted per-turn costs sum back to the final cumulative. That arithmetic is
//     never performed by backend.ts.
//   - the context gauge: pi's REAL `calculateContextTokens`, imported from
//     @earendil-works/pi-coding-agent — the function that actually drives the
//     footer percentage and auto-compaction, not our restatement of it.
//   - the overflow verdict: pi's REAL `isContextOverflow`, imported from
//     @earendil-works/pi-ai — the function that actually compacted the live
//     session — driven by the incident's own numbers to scale.
//
// backend.ts imports its siblings with `.js` suffixes (the root/jiti runtime
// convention), so — like check-acp-prompt-lifecycle — we tsc-emit the project and
// import the COMPILED backend.js whose `.js` imports resolve to real siblings.

import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, rmdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { Api, AssistantMessage, AssistantMessageEvent, Context, Message, Model } from "@earendil-works/pi-ai";
import { isContextOverflow } from "@earendil-works/pi-ai";
import { calculateContextTokens } from "@earendil-works/pi-coding-agent";

const claude = { id: "claude-sonnet-5" } as unknown as Model<Api>;
const cortex = { id: "cortex-auto" } as unknown as Model<Api>;

type Stream = AsyncIterable<AssistantMessageEvent>;

/** The wire shape of one ACP `PromptResponse.usage` (SDK `Usage`). */
interface WireUsage {
	totalTokens: number;
	inputTokens: number;
	outputTokens: number;
	cachedReadTokens?: number;
	cachedWriteTokens?: number;
}

/**
 * One `_meta.quota.token_count` row. The field NAMES deliberately differ from
 * `PromptResponse.usage`: cache reads are `cachedInputTokens` here because the
 * shape is shared with codex-acp, and `cachedWriteTokens` is Claude's extra
 * sibling (read at claude-agent-acp 0.75.1 `dist/acp-agent.js:6493-6502`).
 * Reading a quota row with the `usage` field names silently yields zeros, so the
 * fixture below spells the vendor's names out rather than reusing `WireUsage`.
 */
interface QuotaTokenCount {
	totalTokens?: number;
	inputTokens?: number;
	cachedInputTokens?: number;
	cachedWriteTokens?: number;
	outputTokens?: number;
}

/** What ONE turn of the fake backend reports. */
interface TurnScript {
	usage?: WireUsage;
	/** `_meta.quota.model_usage` — the vendor's ACCOUNTING-grade per-model totals,
	 *  which also count Task subagents, sidechains and internal calls such as
	 *  compaction. Present from claude-agent-acp 0.71.0 (`turnQuotaMeta`). */
	modelUsage?: Array<{ model: string; token_count: QuotaTokenCount }>;
	/** the backend's RUNNING SESSION TOTAL at the end of this turn, in USD */
	cumulativeCostUsd?: number;
	/** post-turn context occupancy (`usage_update.used`) */
	occupancyTokens?: number;
}

const EMPTY_MCP_HASH = "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945";
const DEFAULT_RESOLVED_CONFIG: any = {
	settingSources: [],
	strictMcpConfig: true,
	showToolNotifications: true,
	mcpServers: [],
	mcpServersHash: EMPTY_MCP_HASH,
	tools: ["Read"],
	skillPlugins: [],
	permissionAllow: ["Read(*)"],
	disallowedTools: [],
};

function makeFakeChild() {
	const pipe = () => ({ destroy() {}, unref() {} });
	return {
		pid: 4242,
		exitCode: null as number | null,
		signalCode: null as NodeJS.Signals | null,
		stdin: pipe(),
		stdout: pipe(),
		stderr: {
			on() {},
			once() {},
			destroy() {},
			unref() {},
		},
		kill() {
			return true;
		},
		unref() {},
		once() {},
	};
}

/**
 * One backend world whose turns are SCRIPTED.
 *
 * Each `prompt` call consumes the next TurnScript: it first pushes that turn's
 * `usage_update` notification (the wire the running cost total actually arrives
 * on — read at claude-agent-acp 0.75.1 `dist/acp-agent.js:3467-3482`), then answers the
 * prompt with that turn's `PromptResponse.usage` (the wire the turn aggregate
 * arrives on). Both orderings are the real one: the notification precedes the
 * response, because the SDK emits it from the `result` message that ENDS the turn.
 */
function makeHarness(recordDir: string, scripts: TurnScript[]) {
	const children: ReturnType<typeof makeFakeChild>[] = [];
	let turnIndex = 0;
	let newSessionCalls = 0;

	const makeConnection = (handlers: any) => ({
		initialize: async () => ({ agentCapabilities: {} }),
		newSession: async () => {
			newSessionCalls++;
			return { sessionId: "ACP-1" };
		},
		setSessionConfigOption: async () => ({}),
		prompt: async ({ sessionId }: any) => {
			const script = scripts[turnIndex++] ?? {};
			const update: Record<string, unknown> = { sessionUpdate: "usage_update" };
			let notify = false;
			if (typeof script.occupancyTokens === "number") {
				update.used = script.occupancyTokens;
				notify = true;
			}
			if (typeof script.cumulativeCostUsd === "number") {
				update.cost = { amount: script.cumulativeCostUsd, currency: "USD" };
				notify = true;
			}
			if (notify) await handlers.sessionUpdate({ update, sessionId });
			return {
				stopReason: "end_turn",
				...(script.usage ? { usage: script.usage } : {}),
				...(script.modelUsage ? { _meta: { quota: { model_usage: script.modelUsage } } } : {}),
			};
		},
		cancel: () => {},
		close: () => {},
	});

	return {
		children,
		get turnsPrompted() {
			return turnIndex;
		},
		get newSessionCalls() {
			return newSessionCalls;
		},
		deps: {
			resolveLaunch: () => ({ command: "node", args: ["fake"] }),
			ensureOverlay: () => {},
			spawnChild: () => {
				const c = makeFakeChild();
				children.push(c);
				return c;
			},
			createConnection: (_child: any, handlers: any) => makeConnection(handlers),
			lifecyclePolicy: () => "process-scoped",
			loadConfig: () => DEFAULT_RESOLVED_CONFIG,
			now: () => "2026-09-01T00:00:00Z",
			sessionDir: recordDir,
		},
	};
}

async function collect(stream: Stream): Promise<AssistantMessageEvent[]> {
	const events: AssistantMessageEvent[] = [];
	for await (const ev of stream) events.push(ev);
	return events;
}

/** The sealed assistant message of a finished turn. */
function sealedMessage(events: AssistantMessageEvent[]): AssistantMessage {
	const seal = events.filter((e) => e.type === "done" || e.type === "error") as any[];
	assert.equal(seal.length, 1, "each turn seals exactly once");
	assert.equal(seal[0].type, "done", `the scripted turn must end as a normal done, got ${seal[0].type}`);
	return seal[0].message as AssistantMessage;
}

const userCtx = (text: string): Context => ({ messages: [{ role: "user", content: text, timestamp: 0 }] }) as Context;

const zeroUsage = () => ({
	input: 0,
	output: 0,
	cacheRead: 0,
	cacheWrite: 0,
	totalTokens: 0,
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
});

/** A reuse-shaped context: prior user, assistant, new user. */
function reuseCtx(prior: string, latest: string): Context {
	return {
		messages: [
			{ role: "user", content: prior, timestamp: 0 },
			{
				role: "assistant",
				content: [{ type: "text", text: "ok" }],
				api: "x",
				provider: "x",
				model: "x",
				usage: zeroUsage(),
				stopReason: "stop",
				timestamp: 0,
			} as unknown as Message,
			{ role: "user", content: latest, timestamp: 0 },
		],
	} as Context;
}

/** A third turn on the same reused session. */
function reuseCtx3(a: string, b: string, c: string): Context {
	const assistant = {
		role: "assistant",
		content: [{ type: "text", text: "ok" }],
		api: "x",
		provider: "x",
		model: "x",
		usage: zeroUsage(),
		stopReason: "stop",
		timestamp: 0,
	} as unknown as Message;
	return {
		messages: [
			{ role: "user", content: a, timestamp: 0 },
			assistant,
			{ role: "user", content: b, timestamp: 0 },
			assistant,
			{ role: "user", content: c, timestamp: 0 },
		],
	} as Context;
}

const TMP_EMIT = ".tmp-verify/acp-usage-accounting";
rmSync(TMP_EMIT, { recursive: true, force: true });
const recordDir = mkdtempSync(resolve(tmpdir(), "acp-usage-acct-"));

try {
	execFileSync("node_modules/.bin/tsc", ["--outDir", TMP_EMIT, "--rootDir", ".", "--noEmit", "false"], {
		stdio: "pipe",
	});
	const promptsOut = resolve(TMP_EMIT, "pi-extensions/lib/acp/prompts");
	mkdirSync(promptsOut, { recursive: true });
	copyFileSync("pi-extensions/lib/acp/prompts/engraving.md", resolve(promptsOut, "engraving.md"));
	const backend = (await import(pathToFileURL(resolve(TMP_EMIT, "pi-extensions/lib/acp/backend.js")).href)) as any;

	// ----------------------------------------------------------------------
	// CELL 1 — the turn aggregate never reaches pi's per-request fields.
	//
	// This is the incident's shape: the four ACP totals belong on `usage.acp`, not
	// on pi's request-shaped fields. Four distinct non-zero values keep a mutant
	// from passing by cross-wiring fields; the incident-scale aggregate stays a
	// deterministic receipt, while the live ledger remains a separate receipt.
	// ----------------------------------------------------------------------
	{
		// The 2026-09-02 incident, to scale: ACP reported the turn's ROUND-TRIP
		// AGGREGATE (cacheRead 4,185,084 over 21 requests) while the context that
		// turn actually occupied was 223,516 on a 1,000,000 window.
		const h = makeHarness(recordDir, [
			{
				usage: {
					inputTokens: 42,
					outputTokens: 17_676,
					cachedReadTokens: 4_185_084,
					cachedWriteTokens: 221_084,
					totalTokens: 4_423_886,
				},
				cumulativeCostUsd: 1.5,
				occupancyTokens: 223_516,
			},
		]);
		const msg = sealedMessage(
			await collect(backend.streamAcpTurn(claude, userCtx("turn one"), { sessionId: "usage-A" }, h.deps) as Stream),
		);

		// pi's REAL overflow detector — the function that actually fired on the live
		// session — is the oracle for this claim, not our restatement of its
		// arithmetic, and it is asserted FIRST so that a re-projected aggregate is
		// caught BY THIS CLAIM rather than incidentally by the field comparison
		// below. It reads `input + cacheRead` RAW and never consults totalTokens, so
		// an honest totalTokens cannot rescue a projected aggregate.
		assert.equal(
			isContextOverflow(msg, 1_000_000),
			false,
			"[QK:ACP-TURN-AGGREGATE-NOT-PROJECTED] pi's own isContextOverflow must not fire on a turn whose context " +
				"occupied 223,516 of a 1,000,000 window. With the aggregate projected it read 42 + 4,185,084 and " +
				`compacted the session — the defect this cell exists to keep dead. Got usage: ${JSON.stringify(msg.usage)}`,
		);

		assert.deepEqual(
			{
				input: msg.usage.input,
				output: msg.usage.output,
				cacheRead: msg.usage.cacheRead,
				cacheWrite: msg.usage.cacheWrite,
			},
			{ input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			"ACP's only token carrier is the SUM over this turn's API round " +
				"trips; pi's four fields mean ONE REQUEST's prompt shape. Projecting the aggregate onto them is what " +
				"compacted a live 223k session on a 1M window, invented two phantom cache misses and silenced the one " +
				`real 195,177-token miss. No honest per-request value exists on this wire, so all four stay 0. Got: ${JSON.stringify(msg.usage)}`,
		);

		// pi's OWN reader of this message decides the context gauge and auto-compaction.
		assert.equal(
			calculateContextTokens(msg.usage),
			223_516,
			"[QK:ACP-CONTEXT-OCCUPANCY-PRESERVED] `totalTokens` is what pi reads as CONTEXT OCCUPANCY " +
				"(calculateContextTokens returns it whenever it is non-zero), and the backend reports occupancy on " +
				"usage_update.used — 223516 here. Overwriting it with this turn's aggregate (4423886) would send the " +
				"status-line percentage and auto-compaction reading past the window on a session that fits inside it. " +
				`Got: ${calculateContextTokens(msg.usage)}`,
		);
	}

	// ----------------------------------------------------------------------
	// CELL 1b — the turn's ACCOUNTING aggregate rides its own key.
	//
	// pi's four fields stay 0 (CELL 1); the vendor's four numbers must still reach
	// the operator, on a key no pi reader mistakes for a per-request shape.
	// ----------------------------------------------------------------------
	{
		const h = makeHarness(recordDir, [
			{
				usage: {
					inputTokens: 42,
					outputTokens: 17_676,
					cachedReadTokens: 4_185_084,
					cachedWriteTokens: 221_084,
					totalTokens: 4_423_886,
				},
				cumulativeCostUsd: 1.5,
				occupancyTokens: 223_516,
			},
		]);
		const msg = sealedMessage(
			await collect(backend.streamAcpTurn(claude, userCtx("turn one"), { sessionId: "usage-A2" }, h.deps) as Stream),
		);
		assert.deepEqual(
			(msg.usage as unknown as { acp?: unknown }).acp,
			{ input: 42, output: 17_676, cacheRead: 4_185_084, cacheWrite: 221_084 },
			"[QK:ACP-TURN-ACCOUNTING-ATTACHED] the vendor's four turn totals must reach the message VERBATIM on their own " +
				"key. Dropping them is the silence #93 refused: a session runs for hours on a cache-effect badge while a " +
				"full prefix rewrite has already been paid for, and nothing says so. " +
				`Got: ${JSON.stringify((msg.usage as unknown as { acp?: unknown }).acp)}`,
		);
	}

	// ----------------------------------------------------------------------
	// CELL 1e — the ACCOUNTING-GRADE numerator is PREFERRED over the main-loop one.
	//
	// Two token carriers arrive on the same response and they measure DIFFERENT
	// scopes. `PromptResponse.usage` (== `_meta.quota.token_count`) is the MAIN
	// AGENT LOOP only. `_meta.quota.model_usage` comes from `result.modelUsage` and
	// also counts Task subagents, sidechains and INTERNAL CALLS SUCH AS COMPACTION;
	// the vendor states its rows "can total more than `token_count`" and are "the
	// fuller picture, not a decomposition of it" (read at claude-agent-acp 0.75.1
	// `dist/acp-agent.js:6468-6474`).
	//
	// The wide one is required, not merely nicer, because the DENOMINATOR already
	// has that scope: turn cost is the adjacent diff of the backend's running total,
	// which includes those internal calls. Pairing a main-loop numerator with an
	// all-inclusive denominator understates the cache-effect badge EXACTLY when
	// compaction ran — and compaction is a live path again (#94). A silent fallback
	// to the narrow carrier is therefore a misaccounting, not a degraded reading.
	//
	// The fixture drives BOTH carriers at once with deliberately different numbers,
	// so a fallback cannot pass for a preference, and it supplies TWO rows whose sum
	// matches neither row alone — so dropping the row summation fails here too.
	// Row field names are the vendor's (`cachedInputTokens`), which is also why
	// reading a quota row with the `usage` names would surface as zeros right here.
	// ----------------------------------------------------------------------
	{
		const h = makeHarness(recordDir, [
			{
				// main-loop only — what a fallback would report
				usage: {
					inputTokens: 42,
					outputTokens: 17_676,
					cachedReadTokens: 4_185_084,
					cachedWriteTokens: 221_084,
					totalTokens: 4_423_886,
				},
				// accounting-grade — main loop PLUS an internal/compaction call
				modelUsage: [
					{
						model: "claude-sonnet-5",
						token_count: {
							inputTokens: 42,
							outputTokens: 17_676,
							cachedInputTokens: 4_185_084,
							cachedWriteTokens: 221_084,
						},
					},
					{
						model: "claude-haiku-5",
						token_count: {
							inputTokens: 8,
							outputTokens: 1_324,
							cachedInputTokens: 96_000,
							cachedWriteTokens: 12_000,
						},
					},
				],
				cumulativeCostUsd: 1.5,
				occupancyTokens: 223_516,
			},
		]);
		const msg = sealedMessage(
			await collect(backend.streamAcpTurn(claude, userCtx("turn one"), { sessionId: "usage-A5" }, h.deps) as Stream),
		);
		assert.deepEqual(
			(msg.usage as unknown as { acp?: unknown }).acp,
			{ input: 50, output: 19_000, cacheRead: 4_281_084, cacheWrite: 233_084 },
			"[QK:ACP-ACCOUNTING-PREFERS-WIDEST] the accounting-grade `_meta.quota.model_usage` rows must be SUMMED and " +
				"preferred over the main-loop `PromptResponse.usage`. Falling back to the narrow carrier while turn cost " +
				"stays an all-inclusive diff understates the cache-effect badge exactly when compaction or a subagent ran — " +
				"a silent misaccounting of the same class #93 exists to end. The main-loop-only answer would be " +
				`{input:42,output:17676,cacheRead:4185084,cacheWrite:221084}. Got: ${JSON.stringify((msg.usage as unknown as { acp?: unknown }).acp)}`,
		);
	}

	// ----------------------------------------------------------------------
	// CELL 1c — a re-billed prefix is REPORTED, and its size is a proven bound.
	//
	// Both turns are the 2026-09-01 incident's own aggregates as entwurf saw them.
	// Turn A ends at occupancy 195,627; turn B is the one after the 401-minute idle
	// gap. Two ledger numbers describe that first request and they are NOT the same
	// quantity: it WROTE 195,814 (cache creation) and it MISSED 195,177 (the cache
	// read it would have got had the prefix survived — the identity break). They
	// differ because the prompt grew a little between the two turns. The bound:
	//   195,627 − (4 + 1,220) − max(0, 223,516 − 221,084) = 191,971
	// is compared against the MISS, 195,177 — so the
	// bound is BELOW the truth, which is what makes it a bound and not a guess.
	// ----------------------------------------------------------------------
	{
		const h = makeHarness(recordDir, [
			{
				usage: {
					inputTokens: 4,
					outputTokens: 1_220,
					cachedReadTokens: 387_477,
					cachedWriteTokens: 2_085,
					totalTokens: 390_786,
				},
				cumulativeCostUsd: 10,
				occupancyTokens: 195_627,
			},
			{
				usage: {
					inputTokens: 42,
					outputTokens: 17_676,
					cachedReadTokens: 4_185_084,
					cachedWriteTokens: 221_084,
					totalTokens: 4_423_886,
				},
				cumulativeCostUsd: 14.745,
				occupancyTokens: 223_516,
			},
		]);
		const warm = sealedMessage(
			await collect(backend.streamAcpTurn(claude, userCtx("warm NONCE"), { sessionId: "usage-M" }, h.deps) as Stream),
		);
		const afterGap = sealedMessage(
			await collect(
				backend.streamAcpTurn(
					claude,
					reuseCtx("warm NONCE", "after gap NONCE"),
					{ sessionId: "usage-M" },
					h.deps,
				) as Stream,
			),
		);
		assert.equal(h.children.length, 1, "both turns ran on ONE reused child — the prior-turn facts must survive it");

		const textOf = (m: AssistantMessage): string => m.content.map((c) => (c.type === "text" ? c.text : "")).join("");

		assert.ok(
			!/cache miss/.test(textOf(warm)),
			"the FIRST turn has no previous occupancy to compare against, so it must say nothing. A notice here would " +
				`mean the bound fires on an unknown, which is a guess. Got: ${JSON.stringify(textOf(warm))}`,
		);
		assert.match(
			textOf(afterGap),
			/cache miss ≥192k re-billed/,
			"[QK:ACP-CACHE-REBILL-REPORTED] a re-billed prefix must be SAID. Silence is not a modest reading, it is a " +
				"false one — this turn's first request wrote 195,814 tokens of cache after a 401-minute idle gap, missing " +
				"a 195,177-token read it would otherwise have had, and the operator saw nothing. The bound (191,971) " +
				`rounds to 192k and sits below that miss, which is what makes it a bound. Got: ${JSON.stringify(textOf(afterGap))}`,
		);
		// $4.745 renders as $4.74, and the reason is worth stating so a future reader
		// does not "fix" it: `toFixed(2)` rounds the Number it receives, while the
		// adjacent subtraction is 4.744999999999999 rather than decimal 4.745.
		// Money is shown to the cent; a sub-cent tail is not worth a wider field, and
		// no number the backend never reported is invented either way.
		assert.ok(
			/this turn \$4\.74/.test(textOf(afterGap)),
			"the notice must quote what the turn cost, taken from the SDK's own adjacent diff (14.745 − 10 = 4.745) and " +
				`never from a local repricing. Got: ${JSON.stringify(textOf(afterGap))}`,
		);
		// The idle clause needs a real gap; a same-process gate cannot age the clock,
		// so its absence here is correct and the 401m form stays a LIVE observation.
		assert.ok(
			!/0m idle/.test(textOf(afterGap)),
			`a sub-minute gap must not be announced as idle. Got: ${JSON.stringify(textOf(afterGap))}`,
		);
	}

	// ----------------------------------------------------------------------
	// CELL 1d — NEGATIVE CONTROLS for the re-billed claim.
	//
	// The bound is arithmetic over four numbers; these are the inputs that would
	// make it lie. Each one is reachable on this rail, not a thought experiment.
	// ----------------------------------------------------------------------
	{
		// (i) A context SHRINK — organic compaction inside the child. Occupancy
		// collapses while almost nothing is written. The raw bound reads 180,000;
		// the clamp answers 1,000, which is under the floor, so NOTHING is said.
		// (counterexample from gpt-5.6-sol, 2026-09-02)
		const h = makeHarness(recordDir, [
			{
				usage: {
					inputTokens: 500,
					outputTokens: 500,
					cachedReadTokens: 0,
					cachedWriteTokens: 2_000,
					totalTokens: 3_000,
				},
				cumulativeCostUsd: 1,
				occupancyTokens: 200_000,
			},
			{
				usage: {
					inputTokens: 100,
					outputTokens: 400,
					cachedReadTokens: 0,
					cachedWriteTokens: 1_000,
					totalTokens: 1_500,
				},
				cumulativeCostUsd: 2,
				occupancyTokens: 20_000,
			},
		]);
		const textOf = (m: AssistantMessage): string => m.content.map((c) => (c.type === "text" ? c.text : "")).join("");
		await collect(backend.streamAcpTurn(claude, userCtx("big NONCE"), { sessionId: "usage-N" }, h.deps) as Stream);
		const shrunk = sealedMessage(
			await collect(
				backend.streamAcpTurn(
					claude,
					reuseCtx("big NONCE", "shrunk NONCE"),
					{ sessionId: "usage-N" },
					h.deps,
				) as Stream,
			),
		);
		assert.ok(
			!/cache miss/.test(textOf(shrunk)),
			"[QK:ACP-REBILL-NEVER-EXCEEDS-WRITE] a turn that WROTE 1,000 tokens cannot have re-billed 180,000. The raw " +
				"telescoped bound says 200,000 − 1,000 − 19,000 = 180,000 because occupancy collapsed, but a re-billed " +
				"prefix is paid for as cache creation, so the claim is capped by this turn's own cacheWrite. Without " +
				`that cap an organic compaction announces a six-figure miss that never happened. Got: ${JSON.stringify(textOf(shrunk))}`,
		);
	}

	// ----------------------------------------------------------------------
	// CELL 1f — the bound's IO terms are MAIN-LOOP, never the wide accounting rows.
	//
	// Occupancy (`usage_update.used`) is MAIN-CONTEXT occupancy. The recurrence
	// identity that produces the bound is a property of the MAIN AGENT LOOP's
	// cache breakpoints. `_meta.quota.model_usage` is a WIDER scope: the vendor
	// states those rows also count Task subagents, sidechains, and INTERNAL
	// CALLS SUCH AS COMPACTION (read at claude-agent-acp 0.75.1
	// `dist/acp-agent.js:6465-6485`). Mixing the two scopes inflates the bound
	// through both remaining terms that mention cacheWrite:
	//   max(0, occupancy − cacheWrite) shrinks as wide cacheWrite grows, so
	//   less is subtracted; min(rawBound, cacheWrite) rises with it.
	// Either path can push a WARM main prefix over the notice floor and attach
	// this turn's all-inclusive dollar figure to a miss that did not happen
	// on the prefix — the same class of false dollar assertion #93 exists to end.
	//
	// Constructed, not a live ledger. Turn 1 is a warm main context. Turn 2's
	// MAIN LOOP writes 1,000 tokens of cache; the wide rows write 180,000
	// because an internal/compaction call is included. Mixing those would
	// announce "cache miss ≥174k" (200,000 − 1,000 − max(0, 205,000 − 180,000)
	// = 174,000). The main-loop bound is negative, so nothing is said.
	// `usage.acp` remains the WIDE totals — this cell does not walk back CELL 1e.
	// ----------------------------------------------------------------------
	{
		const h = makeHarness(recordDir, [
			{
				usage: {
					inputTokens: 500,
					outputTokens: 500,
					cachedReadTokens: 0,
					cachedWriteTokens: 2_000,
					totalTokens: 3_000,
				},
				cumulativeCostUsd: 1,
				occupancyTokens: 200_000,
			},
			{
				usage: {
					inputTokens: 100,
					outputTokens: 400,
					cachedReadTokens: 0,
					cachedWriteTokens: 1_000,
					totalTokens: 1_500,
				},
				modelUsage: [
					{
						model: "claude-sonnet-5",
						token_count: {
							inputTokens: 100,
							outputTokens: 400,
							cachedInputTokens: 0,
							cachedWriteTokens: 1_000,
						},
					},
					{
						model: "claude-haiku-5",
						token_count: {
							inputTokens: 8,
							outputTokens: 1_324,
							cachedInputTokens: 0,
							cachedWriteTokens: 179_000,
						},
					},
				],
				cumulativeCostUsd: 5,
				occupancyTokens: 205_000,
			},
		]);
		const textOf = (m: AssistantMessage): string => m.content.map((c) => (c.type === "text" ? c.text : "")).join("");
		await collect(
			backend.streamAcpTurn(claude, userCtx("warm prefix NONCE"), { sessionId: "usage-S" }, h.deps) as Stream,
		);
		const mixed = sealedMessage(
			await collect(
				backend.streamAcpTurn(
					claude,
					reuseCtx("warm prefix NONCE", "compaction sidecar NONCE"),
					{ sessionId: "usage-S" },
					h.deps,
				) as Stream,
			),
		);
		assert.ok(
			!/cache miss/.test(textOf(mixed)),
			"[QK:ACP-REBILL-MAIN-LOOP-SCOPE] a warm main prefix that wrote 1,000 tokens of cache cannot announce a " +
				"174k miss because an internal/compaction call wrote 179,000 more on the WIDE rows. Occupancy and the " +
				"recurrence are main-loop; mixing them with wide cacheWrite inflates the bound through both remaining " +
				"terms and attaches this turn's dollar figure to a miss that did not happen on the prefix. " +
				`Got: ${JSON.stringify(textOf(mixed))}`,
		);
		assert.deepEqual(
			(mixed.usage as unknown as { acp?: unknown }).acp,
			{ input: 108, output: 1_724, cacheRead: 0, cacheWrite: 180_000 },
			"…and usage.acp must still be the WIDE totals (CELL 1e). Narrowing the bound must not silently fall back " +
				`the reporting numerator. Got: ${JSON.stringify((mixed.usage as unknown as { acp?: unknown }).acp)}`,
		);
	}

	// ----------------------------------------------------------------------
	// CELL 2 — two turns' costs SUM to the backend's session total.
	//
	// The series is cumulative and monotone, exactly as the live ledgers were.
	// The subject never computes this sum; this file does.
	// ----------------------------------------------------------------------
	{
		const C1 = 1.5;
		const C2 = 2.75;
		const h = makeHarness(recordDir, [
			{ cumulativeCostUsd: C1, occupancyTokens: 100_000, usage: makeUsage(10) },
			{ cumulativeCostUsd: C1 + C2, occupancyTokens: 180_000, usage: makeUsage(20) },
		]);
		const t1 = sealedMessage(
			await collect(
				backend.streamAcpTurn(claude, userCtx("first NONCE-1"), { sessionId: "usage-B" }, h.deps) as Stream,
			),
		);
		const t2 = sealedMessage(
			await collect(
				backend.streamAcpTurn(
					claude,
					reuseCtx("first NONCE-1", "second NONCE-2"),
					{ sessionId: "usage-B" },
					h.deps,
				) as Stream,
			),
		);
		assert.equal(h.children.length, 1, "both turns ran on ONE reused child — the baseline must survive a reuse turn");

		const perTurn = [t1.usage.cost.total, t2.usage.cost.total];
		assert.equal(
			round6(perTurn[0] + perTurn[1]),
			round6(C1 + C2),
			"[QK:ACP-TURN-COST-SUM-MATCHES-SDK] the backend reports a RUNNING SESSION TOTAL (its own ESTIMATE, not a bill), so a turn " +
				"cost is the ADJACENT DIFF of consecutive totals — and the per-turn costs must then sum back to the " +
				"final total. Assigning the cumulative to the turn field instead is the #93 defect: pi sums per-turn " +
				`costs, which is how a $24.261 session was displayed as $444.370. Got per-turn ${JSON.stringify(perTurn)}`,
		);
		assert.deepEqual(
			perTurn.map(round6),
			[round6(C1), round6(C2)],
			"…and each turn carries ITS OWN diff, not the running total",
		);
	}

	// ----------------------------------------------------------------------
	// CELL 3 — a turn with NO cost notification holds the baseline.
	//
	// Measured upstream: the result-path `usage_update` carries cost (read at
	// claude-agent-acp 0.75.1 `dist/acp-agent.js:3467-3482`), while other
	// `usage_update` paths can carry `used` without cost (for example the
	// rate-limit path at `:4269-4277`). A live thinkpad ledger shows such turns
	// really occur. The honest handling is to HOLD the baseline so the amount lands
	// in the NEXT diff: misattributed by turn, exact by session. Rebaselining to 0
	// there would double-count the whole prefix.
	//
	// The same turn also proves the OCCUPANCY carry-forward: with no notification
	// there is no fresh `used`, and before this lane such a message was all-zero
	// and pi skipped it. Now it carries accounting on `usage.acp` while pi's four
	// fields remain zero, so a zero totalTokens would leave no direct occupancy for
	// the gauge to use.
	// ----------------------------------------------------------------------
	{
		const C1 = 1.5;
		const C3 = 4.25;
		const h = makeHarness(recordDir, [
			{ cumulativeCostUsd: C1, occupancyTokens: 120_000, usage: makeUsage(10) },
			{ usage: makeUsage(20) },
			{ cumulativeCostUsd: C3, occupancyTokens: 260_000, usage: makeUsage(30) },
		]);
		const t1 = sealedMessage(
			await collect(
				backend.streamAcpTurn(claude, userCtx("first NONCE-1"), { sessionId: "usage-C" }, h.deps) as Stream,
			),
		);
		const t2 = sealedMessage(
			await collect(
				backend.streamAcpTurn(
					claude,
					reuseCtx("first NONCE-1", "second NONCE-2"),
					{ sessionId: "usage-C" },
					h.deps,
				) as Stream,
			),
		);
		const t3 = sealedMessage(
			await collect(
				backend.streamAcpTurn(
					claude,
					reuseCtx3("first NONCE-1", "second NONCE-2", "third NONCE-3"),
					{ sessionId: "usage-C" },
					h.deps,
				) as Stream,
			),
		);
		assert.equal(h.children.length, 1, "all three turns ran on ONE reused child");

		const perTurn = [t1.usage.cost.total, t2.usage.cost.total, t3.usage.cost.total].map(round6);
		assert.deepEqual(
			perTurn,
			[round6(C1), 0, round6(C3 - C1)],
			"[QK:ACP-COST-BASELINE-HELD-WHEN-MISSING] a turn whose cost notification never arrived must attribute $0 " +
				"and HOLD the baseline — its real amount is still inside the backend's running total and the NEXT " +
				"adjacent diff absorbs it. Zeroing or rebaselining there double-counts every dollar spent so far. " +
				`Got ${JSON.stringify(perTurn)}`,
		);
		assert.equal(
			round6(perTurn.reduce((a, b) => a + b, 0)),
			round6(C3),
			"…and the SESSION sum still reproduces the backend's final running total exactly despite the gap",
		);

		assert.equal(
			calculateContextTokens(t2.usage),
			120_000,
			"[QK:ACP-CONTEXT-OCCUPANCY-CARRIED] a turn with no usage_update has no fresh occupancy, but it now DOES carry " +
				"a token partition — so leaving totalTokens at 0 makes pi fall through to that partition and the context " +
				"gauge drops from the real occupancy to one turn's delta. The last measurement must be carried forward " +
				`(assigned, never summed). Got: ${calculateContextTokens(t2.usage)}`,
		);
		assert.equal(
			calculateContextTokens(t3.usage),
			260_000,
			"…and a turn that DOES report occupancy uses the fresh value, never the carried one",
		);
	}

	// ----------------------------------------------------------------------
	// CELL 4 — a DECREASING session total is never silently absorbed.
	//
	// `conversation_reset` switches the session to a fresh transcript (read at
	// claude-agent-acp 0.75.1 `dist/acp-agent.js:4282-4289`), but whether that
	// changes `total_cost_usd` is an SDK-internal value we cannot observe here.
	// A diff can therefore go negative in a session we are still holding.
	// Absorbing it quietly would both misreport the turn and destroy the only
	// observation that could settle the open question.
	// ----------------------------------------------------------------------
	{
		const h = makeHarness(recordDir, [
			{ cumulativeCostUsd: 4.0, occupancyTokens: 300_000, usage: makeUsage(10) },
			{ cumulativeCostUsd: 1.0, occupancyTokens: 40_000, usage: makeUsage(20) },
			{ cumulativeCostUsd: 1.5, occupancyTokens: 60_000, usage: makeUsage(30) },
		]);
		const t1 = sealedMessage(
			await collect(
				backend.streamAcpTurn(claude, userCtx("first NONCE-1"), { sessionId: "usage-D" }, h.deps) as Stream,
			),
		);
		const t2events = await collect(
			backend.streamAcpTurn(
				claude,
				reuseCtx("first NONCE-1", "second NONCE-2"),
				{ sessionId: "usage-D" },
				h.deps,
			) as Stream,
		);
		const t2 = sealedMessage(t2events);
		const t3 = sealedMessage(
			await collect(
				backend.streamAcpTurn(
					claude,
					reuseCtx3("first NONCE-1", "second NONCE-2", "third NONCE-3"),
					{ sessionId: "usage-D" },
					h.deps,
				) as Stream,
			),
		);

		const text = t2.content
			.filter((b: any) => b.type === "text")
			.map((b: any) => b.text)
			.join("");
		assert.equal(round6(t1.usage.cost.total), 4.0, "the first turn is the full running total (baseline starts empty)");
		assert.ok(
			round6(t2.usage.cost.total) === 0 && /cost baseline reset/.test(text) && text.includes("1.000000"),
			"[QK:ACP-COST-RESET-NOT-SILENT] a running total that goes BACKWARDS must rebaseline, attribute $0 for that " +
				"turn, AND tell the operator — with both numbers. Silently absorbing it would report a wrong turn cost " +
				"and erase the only observation that can settle what a conversation reset does to the backend's total. " +
				`Got cost=${t2.usage.cost.total} notice=${JSON.stringify(text)}`,
		);
		assert.equal(
			round6(t3.usage.cost.total),
			0.5,
			"…and after the rebaseline the NEXT turn is measured against the new total (1.5 - 1.0), not the old one",
		);
	}

	// ----------------------------------------------------------------------
	// CELL 5 — a backend with no MEASURED semantics is sealed NOT AT ALL.
	//
	// backend.ts / event-mapper.ts are COMMON layer: cortex drives the same turn
	// loop and the same mapper. Nobody has measured what cortex's ACP `usage`
	// means (turn delta or session total? against which price table?), and ACP's
	// own type is self-contradictory about it — the outer comment says "for this
	// turn", the field comments say "across all turns/session". So cortex must
	// keep exactly its pre-#93 output: the coarse mapper assignment, and no token
	// projection, no baseline, no diff.
	// ----------------------------------------------------------------------
	// TWO turns, and the second one is what carries the claim: on turn ONE a
	// diff-against-an-empty-baseline and the raw cumulative are the SAME number, so
	// a single turn cannot tell "sealed" from "not sealed". Turn two separates them
	// (raw 9.0 vs diff 1.75).
	{
		const h = makeHarness(recordDir, [
			{
				usage: {
					inputTokens: 111,
					outputTokens: 222,
					cachedReadTokens: 333,
					cachedWriteTokens: 444,
					totalTokens: 1110,
				},
				cumulativeCostUsd: 7.25,
				occupancyTokens: 90_000,
			},
			{
				usage: { inputTokens: 11, outputTokens: 22, cachedReadTokens: 33, cachedWriteTokens: 44, totalTokens: 110 },
				cumulativeCostUsd: 9.0,
				occupancyTokens: 140_000,
			},
		]);
		await collect(backend.streamAcpTurn(cortex, userCtx("cortex NONCE-1"), { sessionId: "usage-E" }, h.deps) as Stream);
		const msg = sealedMessage(
			await collect(
				backend.streamAcpTurn(
					cortex,
					reuseCtx("cortex NONCE-1", "cortex NONCE-2"),
					{ sessionId: "usage-E" },
					h.deps,
				) as Stream,
			),
		);
		assert.equal(h.children.length, 1, "both cortex turns ran on ONE reused child");
		assert.deepEqual(
			{
				input: msg.usage.input,
				output: msg.usage.output,
				cacheRead: msg.usage.cacheRead,
				cacheWrite: msg.usage.cacheWrite,
				total: msg.usage.cost.total,
				totalTokens: msg.usage.totalTokens,
			},
			{ input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 9.0, totalTokens: 140_000 },
			"[QK:ACP-CORTEX-USAGE-UNTOUCHED] the sealing must be gated on the ADAPTER declaring measured semantics, not " +
				"on the common turn loop. A backend that declares nothing keeps its pre-#93 output exactly — " +
				"projecting claude's measured semantics onto it would mint, in a second backend, the same unmeasured " +
				`accounting this lane exists to end. Got: ${JSON.stringify(msg.usage)}`,
		);
	}
	// ----------------------------------------------------------------------
	// CELL 6 — the next turn may start THE INSTANT the previous one seals, and
	// the cost baseline must survive that.
	//
	// Every other cell starts turn 2 after fully draining turn 1's stream. A real
	// caller need not be that polite: pi's loop can begin the next turn as soon as
	// it observes the terminal event. If a successfully completed process-scoped
	// session were not yet discoverable at that moment, the next turn would find
	// no session, open a second one, and start from an EMPTY baseline — the whole
	// session's accounting would silently reset at a turn boundary.
	//
	// So this cell is the tightest caller expressible: turn 2 is launched from
	// INSIDE the iteration, synchronously on the `done` event, before turn 1's
	// stream has even finished draining. It holds today because the retention that
	// follows the seal shares its synchronous run (no await between them) and the
	// turn's in-flight claim covers the same span. Both are invariants a later edit
	// could break WITHOUT breaking anything else — an inserted await would let this
	// caller through the gap — which is exactly why the assertion is written here
	// rather than left as a property of the current line order.
	//
	// Deliberately carries NO [QK:…] signature and no mutant. A QK claim is a
	// promise that re-planting a CLOSED defect turns this red, and there is no
	// reachable defect to re-plant: measured on this source, the seal cannot
	// preempt the retention that shares its synchronous run, so the pre-existing
	// line order passes this cell too. Labelling it anyway would mint a claim
	// nothing can kill. It is a REGRESSION LOCK for a future edit, not evidence
	// that a defect was closed.
	// ----------------------------------------------------------------------
	{
		const C1 = 2.0;
		const C2 = 3.5;
		const h = makeHarness(recordDir, [
			{ cumulativeCostUsd: C1, occupancyTokens: 100_000, usage: makeUsage(10) },
			{ cumulativeCostUsd: C1 + C2, occupancyTokens: 210_000, usage: makeUsage(20) },
		]);

		const firstEvents: AssistantMessageEvent[] = [];
		let secondTurn: Promise<AssistantMessageEvent[]> | undefined;
		const firstStream = backend.streamAcpTurn(
			claude,
			userCtx("first NONCE-1"),
			{ sessionId: "usage-F" },
			h.deps,
		) as Stream;
		for await (const ev of firstStream) {
			firstEvents.push(ev);
			// The instant the turn seals — not after the loop, not on a later tick.
			if ((ev.type === "done" || ev.type === "error") && !secondTurn) {
				secondTurn = collect(
					backend.streamAcpTurn(
						claude,
						reuseCtx("first NONCE-1", "second NONCE-2"),
						{ sessionId: "usage-F" },
						h.deps,
					) as Stream,
				);
			}
		}
		assert.ok(secondTurn, "the first turn must have sealed with a terminal event");
		const t1 = sealedMessage(firstEvents);
		const t2 = sealedMessage(await secondTurn);

		assert.equal(
			h.children.length,
			1,
			"a turn started the instant the previous one sealed must find " +
				"the completed process-scoped session already discoverable and REUSE it. A second child here means the " +
				"next turn opened its own session, which also means it started from an empty cost baseline — a long " +
				`session's accounting would reset at a turn boundary. Got ${h.children.length} children`,
		);
		assert.equal(h.newSessionCalls, 1, "…and exactly one ACP session was ever created for that key");
		assert.deepEqual(
			[round6(t1.usage.cost.total), round6(t2.usage.cost.total)],
			[round6(C1), round6(C2)],
			"…and the baseline carried across that boundary, so turn 2 is its own diff and not the running total again",
		);
	}
} finally {
	rmSync(TMP_EMIT, { recursive: true, force: true });
	try {
		// The qualification harness's work-surface hash walks ignored paths too, so
		// a leftover EMPTY parent dir reads as IMPURE tree drift even though git
		// porcelain is clean. Remove it when empty; a concurrent sibling gate's
		// emit keeps it alive and this rmdir simply fails.
		rmdirSync(".tmp-verify");
	} catch {
		// non-empty or already gone — fine either way
	}
	rmSync(recordDir, { recursive: true, force: true });
}

/** Distinct-but-uninteresting token partition for the cost-focused cells. */
function makeUsage(seed: number): WireUsage {
	return {
		inputTokens: seed,
		outputTokens: seed * 2,
		cachedReadTokens: seed * 3,
		cachedWriteTokens: seed * 4,
		totalTokens: seed * 10,
	};
}

/** Float compare at 6 decimals — the numbers are USD sums, not bit patterns. */
function round6(value: number): number {
	return Math.round(value * 1e6) / 1e6;
}

console.log(
	"[check-acp-usage-accounting] ok — a Claude ACP turn's ROUND-TRIP AGGREGATE is never projected onto pi's four " +
		"per-request usage fields, so pi's own isContextOverflow does not fire on a session that fits its window; " +
		"the vendor's four turn totals still reach the operator VERBATIM on their own `usage.acp` key, taken from the " +
		"ACCOUNTING-GRADE `_meta.quota.model_usage` rows (summed) in preference to the main-loop-only " +
		"`PromptResponse.usage`, so the numerator's scope matches the all-inclusive cost denominator; a re-billed " +
		"prefix is REPORTED with a size that is a PROVEN LOWER BOUND (191,971 against the ledger's true 195,177) and " +
		"the turn's own SDK cost, computed from MAIN-LOOP usage so a wide compaction write cannot inflate it; " +
		"per-turn costs are ADJACENT DIFFS of the backend's running session total and sum back to it across " +
		"a reused session; a turn with no cost notification attributes $0 while HOLDING the baseline so the session sum " +
		"reproduces the backend's own cumulative ESTIMATE exactly (agreement with that carrier, never with a bill); a DECREASING total rebaselines, attributes $0 and says so to the operator with both numbers; " +
		"totalTokens stays CONTEXT OCCUPANCY (verified through pi's own calculateContextTokens) and is carried forward " +
		"when a turn reports none; a backend that declares no measured semantics — cortex — is sealed not at all; and a next turn " +
		"started from INSIDE the previous turn's terminal event still reuses the one session, so the cost baseline " +
		"survives the turn boundary",
);
