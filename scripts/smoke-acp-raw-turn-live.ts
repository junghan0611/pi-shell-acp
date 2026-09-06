// S2a-2 — raw ACP backend pipe, one live turn. LIVE-gated, OUT of `pnpm check`.
//
//   LIVE=1 ./run.sh smoke-acp-raw-turn-live
//
// What this proves (and ONLY this): the pinned Claude ACP adapter
// (@agentclientprotocol/claude-agent-acp@0.75.1) spawns, speaks the ACP wire
// protocol over stdio NDJSON, and returns one real model turn. It is the
// bytes-flow proof that the S2a dep surface is not just installable but
// actually drivable — before any provider/overlay/streamSimple code (S2b+).
//
// Deliberately NOT here (S2b+ / forbidden ahead of the raw pipe):
//   - no pi provider path, no streamSimple (backend-stub stays fail-loud);
//   - no config overlay, no tool-narrowing, no identity carrier / engraving;
//   - no _meta.systemPrompt (kept absent so the billing carrier never grows);
//   - no mailbox-absence / overlay-active assertions (those need S2b).
//
// Boundary notes (GPT-reviewed):
//   - launch source MUST be the resolved package bin. A silent PATH fallback
//     would hide a dep-pin / pack miss, so it FAILS acceptance unless the
//     operator sets ENTWURF_ACP_RAW_TURN_ALLOW_PATH_FALLBACK=1 (then the run
//     is stamped "debug/non-acceptance").
//   - cwd is a fresh mkdtemp scratch — this isolates the repo, NOT ~/.claude
//     side effects. Without an overlay the adapter reads the operator's own
//     local Claude auth/config; entwurf neither copies nor proxies it.

import { strict as assert } from "node:assert";
import { type ChildProcessByStdio, spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { Readable, Writable } from "node:stream";
import { ndJsonStream, PROTOCOL_VERSION } from "@agentclientprotocol/sdk";
import { connectAcpClient } from "../pi-extensions/lib/acp/acp-client.ts";
import { terminateChild } from "./lib/acp-child-cleanup.ts";
import { skipLive } from "./lib/live-skip.ts";

const REQUESTED_MODEL_ID = process.env.ENTWURF_ACP_RAW_TURN_MODEL ?? "claude-sonnet-5";
const ALLOW_PATH_FALLBACK = process.env.ENTWURF_ACP_RAW_TURN_ALLOW_PATH_FALLBACK === "1";
const RAW_TAIL_CAP = 64 * 1024; // cap captured raw NDJSON to 64KB tail on report.

function fail(msg: string): never {
	console.error(`[smoke-acp-raw-turn-live] FAIL: ${msg}`);
	process.exit(1);
}

// Guard each RPC so a hung backend fails this smoke instead of the outer
// process timeout — keeps the failure attributable to the right step. Always
// clear the timeout; otherwise a successful live turn can print PASS and keep
// Node alive until the stale timer fires.
function withTimeout<T>(label: string, p: Promise<T>, ms: number): Promise<T> {
	let timer: ReturnType<typeof setTimeout> | undefined;
	const timeout = new Promise<never>((_, reject) => {
		timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
	});
	return Promise.race([p, timeout]).finally(() => {
		if (timer) clearTimeout(timer);
	});
}

if (process.env.LIVE !== "1") {
	skipLive("smoke-acp-raw-turn-live", "set LIVE=1 to run the real ACP turn.");
}

// ---------------------------------------------------------------------------
// Launch resolution — package bin only (acceptance), PATH fallback is debug.
// ---------------------------------------------------------------------------
function resolveLaunch(): { command: string; args: string[]; source: string; acceptance: boolean } {
	const require = createRequire(import.meta.url);
	try {
		const pkgJsonPath = require.resolve("@agentclientprotocol/claude-agent-acp/package.json");
		const pkgJson = JSON.parse(readFileSync(pkgJsonPath, "utf8")) as { bin?: string | Record<string, string> };
		const binPath = typeof pkgJson.bin === "string" ? pkgJson.bin : pkgJson.bin?.["claude-agent-acp"];
		if (binPath) {
			return {
				command: process.execPath,
				args: [join(dirname(pkgJsonPath), binPath)],
				source: "package:@agentclientprotocol/claude-agent-acp",
				acceptance: true,
			};
		}
		fail("@agentclientprotocol/claude-agent-acp resolved but exposes no bin entry");
	} catch (err) {
		if (!ALLOW_PATH_FALLBACK) {
			fail(
				`could not resolve @agentclientprotocol/claude-agent-acp package bin (${(err as Error).message}). ` +
					"This is an acceptance failure — the dep pin / install is broken. Set " +
					"ENTWURF_ACP_RAW_TURN_ALLOW_PATH_FALLBACK=1 only for debug.",
			);
		}
	}
	return {
		command: "claude-agent-acp",
		args: [],
		source: "PATH:claude-agent-acp (debug/non-acceptance)",
		acceptance: false,
	};
}

// ---------------------------------------------------------------------------
// Drive one turn.
// ---------------------------------------------------------------------------
async function main(): Promise<void> {
	const launch = resolveLaunch();
	const scratch = await mkdtemp(join(tmpdir(), "entwurf-s2a-raw-"));
	console.error(`[smoke-acp-raw-turn-live] launch source: ${launch.source}`);
	console.error(`[smoke-acp-raw-turn-live] scratch cwd:   ${scratch}`);
	console.error(`[smoke-acp-raw-turn-live] model request:  ${REQUESTED_MODEL_ID}`);

	const child: ChildProcessByStdio<Writable, Readable, Readable> = spawn(launch.command, launch.args, {
		cwd: scratch,
		env: { ...process.env },
		stdio: ["pipe", "pipe", "pipe"],
	}) as ChildProcessByStdio<Writable, Readable, Readable>;

	const stderrTail: string[] = [];
	child.stderr.on("data", (c) => {
		stderrTail.push(c.toString());
		if (stderrTail.length > 200) stderrTail.shift();
	});

	// Tee stdout so we capture the raw NDJSON bytes the SDK consumes.
	let rawBytes = "";
	child.stdout.on("data", (c) => {
		rawBytes += c.toString();
		if (rawBytes.length > RAW_TAIL_CAP * 2) rawBytes = rawBytes.slice(-RAW_TAIL_CAP);
	});

	const stdoutWeb = Readable.toWeb(child.stdout) as unknown as ReadableStream<Uint8Array>;
	const stdinWeb = Writable.toWeb(child.stdin) as unknown as WritableStream<Uint8Array>;
	const stream = ndJsonStream(stdinWeb, stdoutWeb);

	let collectedText = "";
	let unexpectedPermission = 0;
	let unexpectedFileOp = 0;

	const connection = connectAcpClient(stream as any, {
		// agent text chunks land here as sessionUpdate notifications.
		sessionUpdate: async (notification: any) => {
			const u = notification?.update;
			if (u?.sessionUpdate === "agent_message_chunk") {
				const t = u?.content?.text;
				if (typeof t === "string") collectedText += t;
			}
		},
		// A raw "say OK" turn should need no tools / files. Anything else is
		// unexpected — refuse and count it, then fail at the end.
		requestPermission: async (): Promise<any> => {
			unexpectedPermission++;
			return { outcome: { outcome: "cancelled" } };
		},
		readTextFile: async (): Promise<any> => {
			unexpectedFileOp++;
			throw new Error("unexpected readTextFile in raw OK turn");
		},
		writeTextFile: async (): Promise<any> => {
			unexpectedFileOp++;
			throw new Error("unexpected writeTextFile in raw OK turn");
		},
	});

	let failure: Error | null = null;
	try {
		// Acceptance precondition: the launch must be the resolved package bin.
		if (!launch.acceptance) {
			throw new Error("launch was a PATH fallback (debug) — not an acceptance PASS");
		}

		// 1) initialize
		const init = await withTimeout(
			"initialize",
			connection.initialize({
				protocolVersion: PROTOCOL_VERSION,
				clientCapabilities: {},
				clientInfo: { name: "entwurf-smoke", version: "s2a-raw" },
			} as any),
			30_000,
		);
		assert.ok(init, "initialize returned no result");
		console.error(`[smoke-acp-raw-turn-live] initialize ok (protocolVersion=${(init as any)?.protocolVersion})`);

		// 2) newSession — minimal: scratch cwd, no MCP, NO _meta (carrier absent).
		const created = (await withTimeout(
			"newSession",
			connection.newSession({ cwd: scratch, mcpServers: [] } as any),
			30_000,
		)) as any;
		const sessionId = created?.sessionId;
		assert.ok(sessionId, "newSession returned no sessionId");
		const available = Array.isArray(created?.models)
			? created.models
			: Array.isArray(created?.availableModels)
				? created.availableModels
				: undefined;
		console.error(
			`[smoke-acp-raw-turn-live] newSession ok (sessionId=${String(sessionId).slice(0, 12)}…` +
				(available ? `, models=${available.map((m: any) => m?.modelId ?? m?.id ?? m).join(",")}` : "") +
				")",
		);

		// 3) force the requested model — REQUIRED. If the adapter cannot honor
		//    the switch, the "sonnet" claim would be a lie; fail loudly instead
		//    of silently running the session default.
		const setConfig = (connection as any).setSessionConfigOption;
		if (typeof setConfig !== "function") {
			throw new Error(
				`setSessionConfigOption unsupported — cannot enforce ${REQUESTED_MODEL_ID}; S2a requires honest model enforcement`,
			);
		}
		await withTimeout(
			"setSessionConfigOption",
			setConfig.call(connection, { sessionId, configId: "model", value: REQUESTED_MODEL_ID }),
			30_000,
		);
		console.error(`[smoke-acp-raw-turn-live] model set -> ${REQUESTED_MODEL_ID}`);

		// 4) prompt — one tiny turn, no carrier.
		const promptResult = (await withTimeout(
			"prompt",
			connection.prompt({
				sessionId,
				prompt: [{ type: "text", text: "Reply with exactly OK and nothing else." }],
			} as any),
			120_000,
		)) as any;
		console.error(`[smoke-acp-raw-turn-live] prompt returned (stopReason=${promptResult?.stopReason})`);

		// ---- assertions ----
		assert.ok(promptResult, "prompt returned no result");
		assert.equal(unexpectedPermission, 0, `unexpected permission request(s): ${unexpectedPermission}`);
		assert.equal(unexpectedFileOp, 0, `unexpected file op(s): ${unexpectedFileOp}`);
		assert.ok(rawBytes.trim().length > 0, "no raw NDJSON bytes captured from backend stdout");
		const normalized = collectedText.replace(/\s+/g, " ").trim().toUpperCase();
		assert.ok(
			normalized.includes("OK"),
			`agent text did not contain "OK" (got: ${JSON.stringify(collectedText.slice(0, 200))})`,
		);

		console.log("[smoke-acp-raw-turn-live] PASS — raw ACP turn drove a live model reply");
		console.log(`  launch:    ${launch.source}`);
		console.log(`  model:     ${REQUESTED_MODEL_ID}`);
		console.log(`  reply:     ${JSON.stringify(collectedText.trim().slice(0, 120))}`);
		console.log(`  rawBytes:  ${rawBytes.length} captured (NDJSON)`);
	} catch (err) {
		failure = err instanceof Error ? err : new Error(String(err));
		console.error(`[smoke-acp-raw-turn-live] stderr tail:\n${stderrTail.slice(-20).join("")}`);
		console.error(`[smoke-acp-raw-turn-live] raw NDJSON tail:\n${rawBytes.slice(-2048)}`);
	} finally {
		connection.close?.();
		await terminateChild(child);
		try {
			await rm(scratch, { recursive: true, force: true });
		} catch {
			// scratch cleanup is best-effort
		}
	}

	if (failure) fail(failure.message);
}

await main();
