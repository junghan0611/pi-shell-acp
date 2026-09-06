// RAW MEASUREMENT PROBE — not a gate, not in any check tier.
//
//   LIVE=1 node --experimental-strip-types scripts/raw-acp-compaction-measure/probe.ts
//
// WHY THIS EXISTS. claude-agent-acp 0.75.0 (#991, `f74a517`) stopped surfacing Claude's
// context compaction as assistant text and started surfacing it as a SYNTHETIC ACP tool
// lifecycle: a `tool_call` with `kind: "think"`, title `Compact conversation`, and
// `_meta.contextCompaction` schema v1. Reading the dist says that much
// (`dist/acp-agent.js:31`, `:1877`, `:2711-2742`); it does not say what an entwurf
// operator actually SEES, because that depends on our own `applyAcpSessionUpdate`.
//
// So this probe drives one real `/compact` turn on the pinned adapter, captures the
// tool-lifecycle notifications verbatim, and then replays those exact notifications
// through the PRODUCTION event mapper — the same function backend.ts calls — and prints
// the pi-side transcript fragment they produce. The point is the join: vendor wire on one
// side, our rendered notice on the other, in one receipt.
//
// It asserts nothing and blocks nothing. The receipt goes in README.md next to it.

import { type ChildProcessByStdio, spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable, Writable } from "node:stream";
import { ndJsonStream, PROTOCOL_VERSION } from "@agentclientprotocol/sdk";
import { connectAcpClient } from "../../pi-extensions/lib/acp/acp-client.ts";
import { applyAcpSessionUpdate, createAcpStreamState } from "../../pi-extensions/lib/acp/event-mapper.ts";
import { terminateChild } from "../lib/acp-child-cleanup.ts";

const MODEL_ID = process.env.ENTWURF_ACP_RAW_TURN_MODEL ?? "claude-sonnet-5";
const OUT = process.env.RAW_COMPACTION_OUT ?? join(tmpdir(), "raw-acp-compaction.json");

if (process.env.LIVE !== "1") {
	console.error("[raw-acp-compaction] set LIVE=1 to spend a real turn.");
	process.exit(0);
}

function withTimeout<T>(label: string, p: Promise<T>, ms: number): Promise<T> {
	let timer: ReturnType<typeof setTimeout> | undefined;
	const timeout = new Promise<never>((_, reject) => {
		timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
	});
	return Promise.race([p, timeout]).finally(() => {
		if (timer) clearTimeout(timer);
	});
}

const require = createRequire(import.meta.url);
const bin = require.resolve("@agentclientprotocol/claude-agent-acp/dist/index.js");

const scratch = await mkdtemp(join(tmpdir(), "raw-acp-compaction-"));
const child: ChildProcessByStdio<Writable, Readable, Readable> = spawn(process.execPath, [bin], {
	cwd: scratch,
	env: { ...process.env },
	stdio: ["pipe", "pipe", "pipe"],
}) as ChildProcessByStdio<Writable, Readable, Readable>;

const stderrTail: string[] = [];
child.stderr.on("data", (c) => {
	stderrTail.push(c.toString());
	if (stderrTail.length > 200) stderrTail.shift();
});

const stream = ndJsonStream(
	Writable.toWeb(child.stdin) as unknown as WritableStream<Uint8Array>,
	Readable.toWeb(child.stdout) as unknown as ReadableStream<Uint8Array>,
);

// Every tool-lifecycle notification, verbatim, in arrival order.
const toolUpdates: Record<string, unknown>[] = [];
let agentText = "";

const connection = connectAcpClient(
	stream as never,
	{
		sessionUpdate: async (notification: { update?: Record<string, unknown> }) => {
			const u = notification?.update;
			if (!u) return;
			if (u.sessionUpdate === "tool_call" || u.sessionUpdate === "tool_call_update") {
				toolUpdates.push(structuredClone(u));
			}
			if (u.sessionUpdate === "agent_message_chunk") {
				const t = (u.content as { text?: unknown } | undefined)?.text;
				if (typeof t === "string") agentText += t;
			}
		},
		requestPermission: async () => ({ outcome: { outcome: "cancelled" } }),
		readTextFile: async () => {
			throw new Error("unexpected readTextFile");
		},
		writeTextFile: async () => {
			throw new Error("unexpected writeTextFile");
		},
	} as never,
);

let failure: Error | null = null;
try {
	await withTimeout(
		"initialize",
		connection.initialize({ protocolVersion: PROTOCOL_VERSION, clientCapabilities: {} } as never),
		30_000,
	);
	const session = (await withTimeout(
		"newSession",
		connection.newSession({ cwd: scratch, mcpServers: [] } as never),
		60_000,
	)) as { sessionId?: string };
	const sessionId = session?.sessionId;
	if (!sessionId) throw new Error("newSession returned no sessionId");

	const setConfig = (connection as unknown as { setSessionConfigOption?: unknown }).setSessionConfigOption;
	if (typeof setConfig === "function") {
		await withTimeout(
			"setSessionConfigOption",
			(setConfig as (a: unknown) => Promise<unknown>).call(connection, {
				sessionId,
				configId: "model",
				value: MODEL_ID,
			}),
			30_000,
		);
	}

	// One tiny turn so the transcript has something to compact.
	await withTimeout(
		"seed prompt",
		connection.prompt({
			sessionId,
			prompt: [{ type: "text", text: "Reply with exactly SEED and nothing else." }],
		} as never),
		180_000,
	);
	const seedText = agentText;
	agentText = "";
	const beforeCompact = toolUpdates.length;

	// The compaction turn. `/compact` is the vendor's own trigger for the lifecycle
	// under measurement (`dist/acp-agent.js:2054`, `:2103`).
	const compactResult = (await withTimeout(
		"compact prompt",
		connection.prompt({ sessionId, prompt: [{ type: "text", text: "/compact" }] } as never),
		300_000,
	)) as { stopReason?: string };

	const compactionUpdates = toolUpdates.slice(beforeCompact);

	// Replay the captured notifications through the PRODUCTION mapper.
	const notices: string[] = [];
	const state = createAcpStreamState(
		{ push: (ev: unknown) => notices.push(JSON.stringify(ev)) } as never,
		{ api: "entwurf", provider: "entwurf", model: MODEL_ID } as never,
		{ timestamp: 0 },
	);
	for (const u of compactionUpdates) applyAcpSessionUpdate(state, u);

	const receipt = {
		measuredAt: new Date().toISOString(),
		adapter: JSON.parse(
			(await import("node:fs")).readFileSync(
				require.resolve("@agentclientprotocol/claude-agent-acp/package.json"),
				"utf8",
			),
		).version,
		model: MODEL_ID,
		seedText: seedText.trim().slice(0, 80),
		compactStopReason: compactResult?.stopReason,
		compactionToolUpdates: compactionUpdates,
		mappedContent: state.output.content,
		mappedStreamEvents: notices,
	};
	await writeFile(OUT, `${JSON.stringify(receipt, null, "\t")}\n`, "utf8");
	console.log(`[raw-acp-compaction] receipt -> ${OUT}`);
	console.log(`  adapter:            ${receipt.adapter}`);
	console.log(`  compact stopReason: ${receipt.compactStopReason}`);
	console.log(`  tool updates:       ${compactionUpdates.length}`);
	for (const u of compactionUpdates) {
		console.log(
			`    ${String(u.sessionUpdate)} kind=${String(u.kind ?? "-")} status=${String(u.status ?? "-")} title=${JSON.stringify(u.title ?? null)} meta=${JSON.stringify(u._meta ?? null)}`,
		);
	}
	console.log(`  pi-side content blocks: ${JSON.stringify(state.output.content)}`);
} catch (err) {
	failure = err instanceof Error ? err : new Error(String(err));
	console.error(`[raw-acp-compaction] stderr tail:\n${stderrTail.slice(-20).join("")}`);
} finally {
	connection.close?.();
	await terminateChild(child);
	await rm(scratch, { recursive: true, force: true }).catch(() => {});
}

if (failure) {
	console.error(`[raw-acp-compaction] FAILED: ${failure.message}`);
	process.exit(1);
}
