/**
 * entwurf — entwurf a task to an independent agent process.
 *
 * Spawns a dedicated pi process to run a task rather than using a sub-agent
 * inside the caller. It's inter-process coordination, not recursion inside
 * one session. Local and SSH-remote spawns follow the same pattern.
 *
 * Modes:
 *   sync  — block until completion, return the result. (default)
 *   async — spawn and return immediately; notify the caller session on
 *           completion. The entwurf session persists and is resumable.
 *
 * The sync path lives in `./lib/entwurf-core.js` so the same core can be
 * re-exposed by `mcp/pi-tools-bridge` as an MCP tool — single logic, two
 * surfaces.
 *
 * Async entwurf wiring:
 *   - the caller session exposes a Unix socket via --entwurf-control
 *     (see `pi-extensions/entwurf-control.ts` — the peer extension)
 *   - the entwurf itself runs WITHOUT --entwurf-control, because a socket
 *     server would keep `pi -p` from exiting
 *   - on completion, proc.on('close') injects a followUp message into the
 *     caller session
 *   - entwurf_status reports live state (pid + JSONL parse)
 *
 * Usage:
 *   LLM calls the `entwurf` tool  → a separate pi process is spawned
 *   /entwurf "task"               → command-line form
 *
 * Runtime dependency:
 *   - `pi-extensions/entwurf-control.ts` loaded in the CALLER session, with
 *     `--entwurf-control` enabled there. The entwurf itself does not need
 *     the extension.
 */

import { type ChildProcess, spawn } from "node:child_process";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { AgentToolResult, ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import {
	analyzeSessionFileLike,
	cwdToSessionDir,
	DEFAULT_ENTWURF_MODEL,
	enrichTaskWithProjectContext,
	ensureEntwurfOncePerTarget,
	formatSyncSummary,
	getEntwurfExplicitExtensions,
	getRegistryRouting,
	markEntwurfTargetUsed,
	mirrorChildStderr,
	resolveEntwurfTarget,
	resolveGuardTargetKey,
	runEntwurfResumeSync,
	runEntwurfSync,
} from "./lib/entwurf-core.js";

function getParentSessionId(pi: ExtensionAPI): string {
	const sm = (pi as unknown as { sessionManager?: { getSessionId?: () => string } }).sessionManager;
	return sm?.getSessionId?.() ?? "__no_session__";
}

// ============================================================================
// Constants (async-only)
// ============================================================================

const ENTWURF_ENTRY_TYPE = "entwurf-task";
const SESSIONS_BASE = path.join(os.homedir(), ".pi", "agent", "sessions");

/** Find the entwurf session file for the given taskId by scanning sessions/. */
function findEntwurfSession(taskId: string): string | null {
	const active = activeEntwurfs.get(taskId);
	if (active?.sessionFile) return active.sessionFile;

	try {
		for (const dir of fs.readdirSync(SESSIONS_BASE)) {
			const dirPath = path.join(SESSIONS_BASE, dir);
			try {
				if (!fs.statSync(dirPath).isDirectory()) continue;
				for (const file of fs.readdirSync(dirPath)) {
					if (file.includes(`entwurf-${taskId}`)) {
						return path.join(dirPath, file);
					}
				}
			} catch {
				/* skip inaccessible dirs */
			}
		}
	} catch {
		/* sessions base not found */
	}
	return null;
}

// ============================================================================
// Types (async-only)
// ============================================================================

interface AsyncEntwurfInfo {
	taskId: string;
	sessionFile: string;
	pid: number;
	host: string;
	task: string;
	cwd: string;
	model?: string;
	startTime: number;
	status: "running" | "completed" | "failed";
	exitCode?: number;
	output?: string;
	error?: string;
	stopReason?: string;
	explicitExtensions?: string[];
	warnings?: string[];
}

// ============================================================================
// State
// ============================================================================

const activeEntwurfs = new Map<string, AsyncEntwurfInfo & { proc?: ChildProcess }>();

// ============================================================================
// Helpers (async-only)
// ============================================================================

const analyzeSessionFile = analyzeSessionFileLike;

/** Cheap liveness check for a given pid. */
function isProcessAlive(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}

// ============================================================================
// Async entwurf (entwurf-control peer pattern)
// ============================================================================

async function runEntwurfAsync(
	pi: ExtensionAPI,
	task: string,
	options: {
		host?: string;
		cwd?: string;
		provider?: string;
		model?: string;
	},
): Promise<{ taskId: string; sessionFile: string; pid: number }> {
	const host = options.host ?? "local";
	const isRemote = host !== "local";
	const taskId = crypto.randomUUID().slice(0, 8);
	const cwd = options.cwd ?? process.cwd();
	const enrichedTask = enrichTaskWithProjectContext(task, cwd);

	// Entwurf Target Registry: async spawns go through the same gate as sync.
	// Identity Preservation Rule: only spawn paths consult the registry; resume
	// paths preserve the recorded identity verbatim.
	const fallbackModel = options.model && options.model.trim() ? options.model : DEFAULT_ENTWURF_MODEL;
	const target = resolveEntwurfTarget({ provider: options.provider, model: fallbackModel });
	const effectiveModel = target.model;

	const sessionDir = cwdToSessionDir(cwd);
	fs.mkdirSync(sessionDir, { recursive: true });

	const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
	const sessionFile = path.join(sessionDir, `${timestamp}_entwurf-${taskId}.jsonl`);
	const routing = getRegistryRouting(target, isRemote);

	// --no-extensions: global extensions would hold the event loop and block
	//                  `pi -p` from exiting after the task completes.
	// No --entwurf-control: the socket server would keep the process alive.
	const piArgs = [
		"--mode",
		"json",
		"-p",
		"--no-extensions",
		...routing.args,
		"--session",
		sessionFile,
		"--provider",
		routing.provider,
		"--model",
		routing.modelOverride ?? target.model,
		enrichedTask,
	];

	const parentSessionId = process.env.PI_SESSION_ID;

	let command: string;
	let args: string[];
	if (isRemote) {
		command = "ssh";
		const envPrefix = parentSessionId ? `PARENT_SESSION_ID=${parentSessionId}` : "";
		const remoteCmd = `cd ${cwd} && ${envPrefix} pi ${piArgs.map((a) => JSON.stringify(a)).join(" ")}`;
		args = [host, remoteCmd];
	} else {
		command = "pi";
		args = piArgs;
	}

	const proc = spawn(command, args, {
		cwd: isRemote ? undefined : cwd,
		shell: false,
		detached: true,
		stdio: ["ignore", "ignore", "pipe"],
		env: {
			...process.env,
			...(parentSessionId ? { PARENT_SESSION_ID: parentSessionId } : {}),
		},
	});
	// Fire-and-forget async: don't let the child's stderr pipe keep the parent's
	// event loop alive. Interactive parents stay alive on their own (REPL), so
	// the `close` listener below still fires and delivers the followUp. In
	// `pi -p`, once the parent's turn ends the loop empties and the parent
	// exits cleanly — the child continues detached and the listener simply
	// doesn't fire (no session left to notify, which is the right outcome).
	proc.unref();
	mirrorChildStderr(proc);

	const pid = proc.pid ?? 0;

	const info: AsyncEntwurfInfo & { proc?: ChildProcess } = {
		taskId,
		sessionFile: isRemote ? `${host}:${sessionFile}` : sessionFile,
		pid,
		host,
		task,
		cwd,
		model: effectiveModel,
		startTime: Date.now(),
		status: "running",
		explicitExtensions: [...routing.names],
		warnings: [...routing.warnings],
		proc,
	};
	activeEntwurfs.set(taskId, info);

	pi.appendEntry(ENTWURF_ENTRY_TYPE, {
		taskId,
		sessionFile: info.sessionFile,
		pid,
		host,
		task,
		cwd,
		model: effectiveModel,
		startTime: info.startTime,
		explicitExtensions: info.explicitExtensions,
		warnings: info.warnings,
	});

	let stderr = "";
	proc.stderr?.on("data", (data: Buffer) => {
		stderr += data.toString();
	});

	proc.on("close", (code) => {
		info.exitCode = code ?? 0;
		info.status = code === 0 ? "completed" : "failed";
		delete info.proc;

		const localSessionFile = isRemote ? null : info.sessionFile;
		if (localSessionFile && fs.existsSync(localSessionFile)) {
			const analysis = analyzeSessionFile(localSessionFile);
			if (analysis.lastModel) info.model = analysis.lastModel;
			info.stopReason = analysis.lastStopReason ?? undefined;
			info.error = analysis.lastError ?? undefined;
			if (!info.error && info.stopReason === "error") {
				info.error = "Entwurf model returned stopReason=error";
			}
			if ((info.error || info.stopReason === "error") && info.exitCode === 0) {
				info.exitCode = 1;
			}
			if (info.error || info.stopReason === "error") info.status = "failed";

			info.output = analysis.lastAssistantText ?? info.error ?? stderr ?? "(no output)";
			const summaryText = analysis.lastAssistantText ?? info.error ?? `exit code ${info.exitCode}`;
			const summary =
				summaryText.slice(0, 2000) + (summaryText.length > 2000 ? "\n(truncated, full: session-recap)" : "");
			const meta = [
				info.explicitExtensions?.length ? `Compat: ${info.explicitExtensions.join(", ")}` : null,
				info.warnings?.length ? `Warnings: ${info.warnings.join(" | ")}` : null,
			]
				.filter(Boolean)
				.join("\n");

			pi.sendMessage(
				{
					customType: "entwurf-complete",
					content: [
						`${info.status === "failed" ? "❌" : "🏁"} entwurf \`${taskId}\` ${info.status} (${host}, ${analysis.turns} turns, $${analysis.cost.toFixed(4)})`,
						meta || null,
						summary,
					]
						.filter(Boolean)
						.join("\n\n"),
					display: true,
					details: {
						taskId,
						host,
						status: info.status,
						turns: analysis.turns,
						cost: analysis.cost,
						error: info.error,
						stopReason: info.stopReason,
						explicitExtensions: info.explicitExtensions,
						warnings: info.warnings,
					},
				},
				{ triggerTurn: true, deliverAs: "followUp" },
			);
		} else if (stderr) {
			info.error = stderr.slice(0, 500);
			info.output = info.error;
			info.status = "failed";
			pi.sendMessage(
				{
					customType: "entwurf-complete",
					content: `❌ entwurf \`${taskId}\` failed (${host}): ${stderr.slice(0, 300)}`,
					display: true,
					details: {
						taskId,
						host,
						status: "failed",
						error: stderr.slice(0, 500),
						explicitExtensions: info.explicitExtensions,
						warnings: info.warnings,
					},
				},
				{ triggerTurn: true, deliverAs: "followUp" },
			);
		}
	});

	proc.on("error", (err) => {
		info.status = "failed";
		info.output = err.message;
		delete info.proc;
	});

	return { taskId, sessionFile: info.sessionFile, pid };
}

// ============================================================================
// Extension Export
// ============================================================================

export default function (pi: ExtensionAPI) {
	// --- session_start: restore active entwurfs ---
	pi.on("session_start", async (_event, ctx) => {
		for (const entry of ctx.sessionManager.getEntries()) {
			if (entry.type === "custom" && (entry as { customType?: string }).customType === ENTWURF_ENTRY_TYPE) {
				const data = (entry as { data?: AsyncEntwurfInfo }).data;
				if (!data?.taskId) continue;

				if (activeEntwurfs.has(data.taskId)) continue;

				const alive = data.pid > 0 && isProcessAlive(data.pid);

				activeEntwurfs.set(data.taskId, {
					...data,
					status: alive ? "running" : "completed",
				});
			}
		}
	});

	// --- entwurf tool (sync + async) ---
	// Extracted schema — inline Type.Object with many Optional + nested Union
	// triggers TS2589 ("Type instantiation excessively deep") under 0.70.0's
	// registerTool generic inference. Extraction flattens one recursion level.
	const entwurfModeSchema = Type.Union([Type.Literal("sync"), Type.Literal("async")], {
		description: "sync: wait for completion (default). async: return immediately with taskId.",
		default: "sync",
	});
	const entwurfParameters = Type.Object({
		task: Type.String({ description: "The task to entwurf" }),
		host: Type.Optional(Type.String({ description: "SSH host (default: 'local'). e.g., 'gpu1i'" })),
		cwd: Type.Optional(Type.String({ description: "Working directory for the entwurf" })),
		provider: Type.Optional(
			Type.String({
				description:
					"Provider id (e.g. 'pi-shell-acp', 'openai-codex'). Pair with `model` to disambiguate against the Entwurf Target Registry.",
			}),
		),
		model: Type.Optional(
			Type.String({
				description:
					"Model id. Qualified ('pi-shell-acp/claude-sonnet-4-6') or bare ('claude-sonnet-4-6'). Bare names must resolve unambiguously in the registry; otherwise pass `provider`.",
			}),
		),
		mode: Type.Optional(entwurfModeSchema),
	});

	// TS2589 workaround — 0.70.0's registerTool generic couples typebox
	// `Static<TParameters>` with `TDetails` inference, and our parameter
	// schemas (Optional + nested Union) push TypeScript past its recursion
	// depth. Each `execute` body still asserts `Promise<AgentToolResult<unknown>>`
	// so the runtime contract is locked; this cast only relaxes the registration
	// boundary. Revisit when pi-coding-agent exposes a type helper that
	// short-circuits the depth (or when typebox narrows Static).
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	const registerTool = pi.registerTool as (def: any) => void;

	registerTool({
		name: "entwurf",
		label: "Entwurf",
		description:
			"Entwurf a task to an independent agent process. Spawns a separate pi instance (local or remote via SSH) and returns the result. Use when a task needs isolated execution or should run on a different machine.\n\nModes:\n- sync (default): Wait for completion, return result.\n- async: Spawn and return immediately. Get notified on completion. Use entwurf_status to check progress.",
		promptSnippet: "Spawn independent agent for isolated task execution (local or SSH remote)",
		promptGuidelines: [
			"Use entwurf for tasks that should run in isolation — different cwd, different machine, or resource-intensive work.",
			"For SSH remote: set host to SSH config name (e.g., 'gpu1i'). The remote must have pi installed.",
			"mode='sync' (default): Wait for completion, return result. Use for quick checks, git status, simple commands.",
			"Spawn routing comes from the Entwurf Target Registry (~/.pi/agent/entwurf-targets.json). Caller passes provider+model (or qualified 'provider/model'); unregistered tuples are refused with a list of allowed targets. Default when omitted: openai-codex/gpt-5.4.",
			"Bare model auto-resolves only when the registry has exactly one non-explicitOnly match. Example: 'gpt-5.4' resolves to native openai-codex; for ACP gpt-5.4, pass provider='pi-shell-acp' explicitly.",
			"mode='async': Spawn and return immediately. Get notified on completion. Use entwurf_status to check progress.",
			"async entwurfs save sessions — use entwurf_status to check, or resume later.",
			"When a task involves research, analysis, writing, or anything that takes more than a few seconds → use async.",
			"Async entwurfs save sessions — use entwurf_status to check, or resume later.",
			"When delegating tasks that produce notes, instruct the entwurf to use llmlog (not botlog). Entwurfd work is agent-to-agent, not public.",
		],
		parameters: entwurfParameters,

		async execute(_toolCallId, params, signal, onUpdate, _ctx): Promise<AgentToolResult<unknown>> {
			const mode = params.mode ?? "sync";

			const guardSessionId = getParentSessionId(pi);
			const guardTargetKey = resolveGuardTargetKey((params as { provider?: string }).provider, params.model);
			ensureEntwurfOncePerTarget(guardSessionId, guardTargetKey);

			if (mode === "async") {
				const result = await runEntwurfAsync(pi, params.task, {
					host: params.host,
					cwd: params.cwd,
					provider: (params as { provider?: string }).provider,
					model: params.model,
				});
				markEntwurfTargetUsed(guardSessionId, guardTargetKey);

				return {
					content: [
						{
							type: "text",
							text: [
								`🚀 Async entwurf spawned`,
								`Task ID: ${result.taskId}`,
								`Session: ${result.sessionFile}`,
								`PID: ${result.pid}`,
								`Host: ${params.host ?? "local"}`,
								"",
								"Use entwurf_status to check progress. You'll be notified on completion.",
							].join("\n"),
						},
					],
					details: {
						taskId: result.taskId,
						sessionFile: result.sessionFile,
						pid: result.pid,
						host: params.host ?? "local",
						mode: "async",
					},
				};
			}

			// sync mode — shares the entwurf-core path with mcp/pi-tools-bridge
			const result = await runEntwurfSync(params.task, {
				host: params.host,
				cwd: params.cwd,
				provider: (params as { provider?: string }).provider,
				model: params.model,
				signal: signal ?? undefined,
				onUpdate: (text) => {
					onUpdate?.({
						content: [{ type: "text", text: `[${params.host ?? "local"}] ${text.slice(0, 200)}...` }],
						details: {},
					});
				},
			});
			markEntwurfTargetUsed(guardSessionId, guardTargetKey);

			// Fail-fast under pi 0.70: AgentToolResult lost `isError`; the contract
			// is now "throw on failure instead of encoding errors in content". A
			// non-zero exit is a entwurf failure — surface it as an exception so
			// the caller cannot treat this as a successful (but empty) result.
			if (result.exitCode !== 0) {
				const summary = formatSyncSummary(result);
				const reason = result.error ? `: ${result.error}` : "";
				throw new Error(
					`entwurf sync failed (exitCode=${result.exitCode}${reason}). ` +
						`host=${result.host} model=${result.model} turns=${result.turns}. ` +
						`Session: ${result.sessionFile}\n\n${summary}`,
				);
			}

			return {
				content: [{ type: "text", text: formatSyncSummary(result) }],
				details: {
					task: result.task,
					host: result.host,
					exitCode: result.exitCode,
					turns: result.turns,
					cost: result.cost,
					model: result.model,
					sessionFile: result.sessionFile,
					error: result.error,
					stopReason: result.stopReason,
					explicitExtensions: result.explicitExtensions,
					warnings: result.warnings,
				},
			};
		},
	});

	// --- entwurf_status tool ---
	registerTool({
		name: "entwurf_status",
		label: "Entwurf Status",
		description:
			"Check status of async entwurf tasks. Without taskId, lists all tracked entwurfs. With taskId, shows detailed status including last message.",
		parameters: Type.Object({
			taskId: Type.Optional(Type.String({ description: "Specific entwurf task ID. Omit to list all." })),
		}),

		async execute(_toolCallId, params, _signal, _onUpdate, _ctx): Promise<AgentToolResult<unknown>> {
			if (params.taskId) {
				const info = activeEntwurfs.get(params.taskId);
				if (!info) {
					// Fail-fast under pi 0.70: explicit unknown taskId is a caller
					// mistake (or a stale reference). Throw rather than return a
					// content-only "not found" message that the model might paper over.
					throw new Error(
						`Unknown entwurf task: ${params.taskId}. ` +
							`The taskId is not tracked by this session — it may belong to a different pi session, ` +
							`have completed and been cleaned up, or never existed. ` +
							`Call entwurf_status without taskId to list active entwurfs.`,
					);
				}

				const alive = info.pid > 0 && isProcessAlive(info.pid);
				if (info.status === "running" && !alive) {
					info.status = "completed";
				}

				let lastMessage: string | null = null;
				let stats = { turns: 0, cost: 0 };
				if (info.host === "local" && fs.existsSync(info.sessionFile)) {
					const analysis = analyzeSessionFile(info.sessionFile);
					lastMessage = analysis.lastAssistantText;
					stats = { turns: analysis.turns, cost: analysis.cost };
					if (analysis.lastModel) info.model = analysis.lastModel;
					info.stopReason = analysis.lastStopReason ?? info.stopReason;
					info.error = analysis.lastError ?? info.error;
					if (!info.error && info.stopReason === "error") {
						info.error = "Entwurf model returned stopReason=error";
					}
					if (info.error || info.stopReason === "error") info.status = "failed";
					if ((info.error || info.stopReason === "error") && info.exitCode === 0) info.exitCode = 1;
				}

				const elapsed = Math.round((Date.now() - info.startTime) / 1000);

				return {
					content: [
						{
							type: "text",
							text: [
								`Task: ${info.taskId}`,
								`Status: ${info.status}`,
								`Host: ${info.host}`,
								`Elapsed: ${elapsed}s`,
								`Turns: ${stats.turns}`,
								`Cost: $${stats.cost.toFixed(4)}`,
								`Session: ${info.sessionFile}`,
								info.model ? `Model: ${info.model}` : null,
								info.exitCode !== undefined ? `Exit: ${info.exitCode}` : null,
								info.stopReason ? `Stop reason: ${info.stopReason}` : null,
								info.explicitExtensions?.length ? `Compat: ${info.explicitExtensions.join(", ")}` : null,
								info.warnings?.length ? `Warnings: ${info.warnings.join(" | ")}` : null,
								info.error ? `Error: ${info.error}` : null,
								lastMessage ? `\nLast message:\n${lastMessage.slice(0, 3000)}` : null,
							]
								.filter(Boolean)
								.join("\n"),
						},
					],
					details: {
						taskId: info.taskId,
						status: info.status,
						host: info.host,
						elapsed,
						turns: stats.turns,
						cost: stats.cost,
						exitCode: info.exitCode,
						model: info.model,
						error: info.error,
						stopReason: info.stopReason,
						explicitExtensions: info.explicitExtensions,
						warnings: info.warnings,
					},
				};
			}

			if (activeEntwurfs.size === 0) {
				return {
					content: [{ type: "text", text: "No active entwurfs." }],
					details: { count: 0 },
				};
			}

			const lines: string[] = [];
			for (const [id, info] of activeEntwurfs) {
				const alive = info.pid > 0 && isProcessAlive(info.pid);
				if (info.status === "running" && !alive) {
					info.status = "completed";
				}
				if (info.host === "local" && fs.existsSync(info.sessionFile)) {
					const analysis = analyzeSessionFile(info.sessionFile);
					if (analysis.lastModel) info.model = analysis.lastModel;
					info.stopReason = analysis.lastStopReason ?? info.stopReason;
					info.error = analysis.lastError ?? info.error;
					if (!info.error && info.stopReason === "error") {
						info.error = "Entwurf model returned stopReason=error";
					}
					if (info.error || info.stopReason === "error") info.status = "failed";
					if ((info.error || info.stopReason === "error") && info.exitCode === 0) info.exitCode = 1;
				}
				const elapsed = Math.round((Date.now() - info.startTime) / 1000);
				const icon = info.status === "running" ? "⏳" : info.status === "completed" ? "✅" : "❌";
				const suffix = info.error ? ` — ${info.error.slice(0, 80)}` : "";
				lines.push(`${icon} ${id} [${info.host}] ${info.status} (${elapsed}s) — ${info.task.slice(0, 60)}${suffix}`);
			}

			return {
				content: [{ type: "text", text: lines.join("\n") }],
				details: { count: activeEntwurfs.size },
			};
		},
	});

	// --- /entwurf command ---
	pi.registerCommand("entwurf", {
		description: "Entwurf task to independent agent — /entwurf [async] [host:] task",
		handler: async (args, ctx) => {
			if (!args?.trim()) {
				ctx.ui.notify(
					"Usage: /entwurf [async] [host:] task\n" +
						"Examples:\n" +
						"  /entwurf check disk space          (sync, default)\n" +
						"  /entwurf async gpu1i: train model  (async, remote)\n" +
						"  /entwurf async build project       (async, long-running)",
					"warning",
				);
				return;
			}

			let host = "local";
			let task = args.trim();
			let mode: "sync" | "async" = "sync";

			if (task.startsWith("async ")) {
				mode = "async";
				task = task.slice(6).trim();
			}

			const colonMatch = task.match(/^(\S+):\s+(.+)$/);
			if (colonMatch) {
				host = colonMatch[1];
				task = colonMatch[2];
			}

			const guardSessionId = getParentSessionId(pi);
			const guardTargetKey = resolveGuardTargetKey(undefined, undefined);
			ensureEntwurfOncePerTarget(guardSessionId, guardTargetKey);

			if (mode === "async") {
				ctx.ui.notify(`🚀 Async delegating to ${host}...`, "info");
				const result = await runEntwurfAsync(pi, task, { host });
				markEntwurfTargetUsed(guardSessionId, guardTargetKey);
				ctx.ui.notify(`✅ Spawned: ${result.taskId} (pid ${result.pid})\nSession: ${result.sessionFile}`, "info");
			} else {
				ctx.ui.notify(`🚀 Delegating to ${host}...`, "info");
				const result = await runEntwurfSync(task, { host });
				markEntwurfTargetUsed(guardSessionId, guardTargetKey);
				ctx.ui.notify(
					`✅ ${host}: ${result.turns} turns, $${result.cost.toFixed(4)}\n${result.output.slice(0, 200)}`,
					result.exitCode === 0 ? "info" : "error",
				);
			}
		},
	});

	// --- entwurf_resume tool ---
	// Identity Preservation Rule (AGENTS.md): the parameter schema intentionally
	// does NOT include a `model` field. The model is locked to the saved session's
	// recorded value (or the in-process spawn-time record). host/cwd may shift
	// between spawn and resume; identity may not.
	//
	// Phase 0.5: `mode` parameter, default "sync". Before Phase 0.5 this surface
	// was implicitly async (detached spawn + followUp); the MCP bridge surface
	// was already sync via runEntwurfResumeSync. Default-sync unifies the two
	// surfaces on what the docs always claimed ("short sync turn"); async stays
	// available as explicit opt-in for long-running resumes. See AGENTS.md
	// § Entwurf Orchestration § Phase 0.5.
	registerTool({
		name: "entwurf_resume",
		label: "Resume Entwurf",
		description:
			"Resume a completed entwurf session. Runs the entwurf's saved session with an additional prompt.\n\n" +
			"Modes:\n" +
			"- sync (default): wait for completion, return result inline. Matches MCP bridge surface.\n" +
			"- async: spawn detached, deliver completion as followUp message to this session. For long-running resumes.\n\n" +
			"Identity Preservation Rule: model is locked to the saved session — this tool does NOT accept a model override. " +
			"host/cwd may change (execution environment is not identity); model may not. " +
			"If the session has no recorded model the resume is refused rather than falling back to a default.",
		parameters: Type.Object({
			taskId: Type.String({ description: "Entwurf task ID to resume" }),
			prompt: Type.String({ description: "Additional prompt to continue the work" }),
			host: Type.Optional(Type.String({ description: "SSH host override (for remote entwurfs)" })),
			mode: Type.Optional(
				Type.Union([Type.Literal("sync"), Type.Literal("async")], {
					description:
						"sync (default): wait for completion, return result inline. async: spawn detached, deliver completion as followUp.",
					default: "sync",
				}),
			),
		}),

		async execute(_toolCallId, params, signal, onUpdate, _ctx): Promise<AgentToolResult<unknown>> {
			const mode = params.mode ?? "sync";

			// Phase 0.5 sync branch — entwurf to core, return inline (mirrors the
			// MCP bridge surface which already used runEntwurfResumeSync directly).
			if (mode === "sync") {
				const info = activeEntwurfs.get(params.taskId);
				const syncHost = params.host ?? info?.host;
				const syncCwd = info?.cwd;
				const result = await runEntwurfResumeSync(params.taskId, params.prompt, {
					host: syncHost,
					cwd: syncCwd,
					signal: signal ?? undefined,
					onUpdate: (text) => {
						onUpdate?.({
							content: [{ type: "text", text: `[${syncHost ?? "local"}] ${text.slice(0, 200)}...` }],
							details: {},
						});
					},
				});

				// Fail-fast under pi 0.70 — non-zero exit from the resumed session is
				// a entwurf failure. Throw so callers can't treat the partial output
				// as a successful resume.
				if (result.exitCode !== 0) {
					const summary = formatSyncSummary(result);
					const reason = result.error ? `: ${result.error}` : "";
					throw new Error(
						`entwurf_resume sync failed (exitCode=${result.exitCode}${reason}). ` +
							`originalTaskId=${params.taskId} resumedTaskId=${result.taskId} ` +
							`host=${result.host} model=${result.model} turns=${result.turns}.\n\n${summary}`,
					);
				}

				return {
					content: [{ type: "text", text: formatSyncSummary(result) }],
					details: {
						task: result.task,
						host: result.host,
						exitCode: result.exitCode,
						turns: result.turns,
						cost: result.cost,
						model: result.model,
						sessionFile: result.sessionFile,
						taskId: result.taskId,
						originalTaskId: params.taskId,
						error: result.error,
						stopReason: result.stopReason,
						explicitExtensions: result.explicitExtensions,
						warnings: result.warnings,
					},
				};
			}

			// Async branch — unchanged pre-Phase-0.5 behavior. Detached spawn,
			// immediate return, completion delivered as followUp message.
			const info = activeEntwurfs.get(params.taskId);

			let sessionFile: string | null = null;
			let host = params.host ?? "local";

			if (info) {
				sessionFile = info.sessionFile;
				host = params.host ?? info.host;
			} else {
				sessionFile = findEntwurfSession(params.taskId);
			}

			if (!sessionFile) {
				// Fail-fast: caller asked to resume a taskId that has no traceable
				// session (not in this session's active-entwurfs map, no match on
				// disk). Throw so the agent stops trying to continue this task.
				throw new Error(
					`Cannot resume entwurf_resume async: session not found for taskId=${params.taskId}. ` +
						`The task may belong to a different pi session, have been cleaned up, ` +
						`or the id may be wrong. Call entwurf_status to list active entwurfs.`,
				);
			}

			const isRemote = host !== "local";
			if (!isRemote && !fs.existsSync(sessionFile)) {
				throw new Error(
					`Cannot resume entwurf_resume async: session file missing at ${sessionFile} ` +
						`(taskId=${params.taskId}, host=${host}). ` +
						`The session record exists in memory but the JSONL on disk is gone — ` +
						`likely cleaned up or deleted externally.`,
				);
			}

			const sessionAnalysis = !isRemote && fs.existsSync(sessionFile) ? analyzeSessionFile(sessionFile) : null;
			// Identity Preservation Rule: prefer in-process spawn-time record (most
			// accurate), then session JSONL recorded model. Refuse if neither — we
			// never invent an identity for a resume.
			const resumeModel = info?.model ?? sessionAnalysis?.lastModel ?? null;
			if (!resumeModel) {
				// Identity Preservation Rule (throwing form). Refuse to resume when
				// neither the in-memory record nor the on-disk session can tell us
				// *which model* this entwurf was. Inventing an identity is worse
				// than stopping — this is the whole point of the rule.
				throw new Error(
					`Cannot resume ${params.taskId}: session has no recorded model ` +
						`(file empty, corrupted, or never reached an assistant turn). ` +
						`Start a fresh entwurf instead — identity must come from the session.`,
				);
			}
			// Pass recorded provider so ACP-routed spawns get re-injected with the
			// pi-shell-acp bridge on resume (otherwise pi cannot resolve the provider
			// and the resume dies silently — see getEntwurfExplicitExtensions guard).
			const explicitExtensions = getEntwurfExplicitExtensions(
				resumeModel,
				isRemote,
				sessionAnalysis?.lastProvider ?? undefined,
			);
			const resumeProvider = explicitExtensions.provider ?? sessionAnalysis?.lastProvider ?? undefined;

			const piArgs = ["--mode", "json", "-p", "--no-extensions", ...explicitExtensions.args];
			if (resumeProvider) piArgs.push("--provider", resumeProvider);
			piArgs.push("--model", explicitExtensions.modelOverride ?? resumeModel, "--session", sessionFile, params.prompt);

			let command: string;
			let args: string[];
			if (isRemote) {
				command = "ssh";
				const remoteCmd = `pi ${piArgs.map((a) => JSON.stringify(a)).join(" ")}`;
				args = [host, remoteCmd];
			} else {
				command = "pi";
				args = piArgs;
			}

			const resumeTaskId = crypto.randomUUID().slice(0, 8);
			const cwd = info?.cwd ?? process.cwd();

			const proc = spawn(command, args, {
				cwd: isRemote ? undefined : cwd,
				shell: false,
				detached: true,
				stdio: ["ignore", "ignore", "pipe"],
			});
			// Same rationale as runEntwurfAsync — see the comment there.
			proc.unref();
			mirrorChildStderr(proc);

			const pid = proc.pid ?? 0;

			const resumeInfo: AsyncEntwurfInfo & { proc?: ChildProcess } = {
				taskId: resumeTaskId,
				sessionFile,
				pid,
				host,
				task: `resume:${params.taskId} — ${params.prompt.slice(0, 60)}`,
				cwd,
				model: resumeModel,
				startTime: Date.now(),
				status: "running",
				explicitExtensions: [...explicitExtensions.names],
				warnings: [...explicitExtensions.warnings],
				proc,
			};
			activeEntwurfs.set(resumeTaskId, resumeInfo);

			pi.appendEntry(ENTWURF_ENTRY_TYPE, {
				taskId: resumeTaskId,
				sessionFile,
				pid,
				host,
				task: resumeInfo.task,
				cwd,
				startTime: resumeInfo.startTime,
				model: resumeInfo.model,
				explicitExtensions: resumeInfo.explicitExtensions,
				warnings: resumeInfo.warnings,
			});

			let stderr = "";
			proc.stderr?.on("data", (data: Buffer) => {
				stderr += data.toString();
			});

			proc.on("close", (code) => {
				resumeInfo.exitCode = code ?? 0;
				resumeInfo.status = code === 0 ? "completed" : "failed";
				delete resumeInfo.proc;

				if (!isRemote && fs.existsSync(sessionFile!)) {
					const analysis = analyzeSessionFile(sessionFile!);
					if (analysis.lastModel) resumeInfo.model = analysis.lastModel;
					resumeInfo.stopReason = analysis.lastStopReason ?? undefined;
					resumeInfo.error = analysis.lastError ?? undefined;
					if (!resumeInfo.error && resumeInfo.stopReason === "error") {
						resumeInfo.error = "Entwurf model returned stopReason=error";
					}
					if ((resumeInfo.error || resumeInfo.stopReason === "error") && resumeInfo.exitCode === 0) {
						resumeInfo.exitCode = 1;
					}
					if (resumeInfo.error || resumeInfo.stopReason === "error") resumeInfo.status = "failed";

					resumeInfo.output = analysis.lastAssistantText ?? resumeInfo.error ?? stderr ?? "(no output)";
					const summaryText = analysis.lastAssistantText ?? resumeInfo.error ?? `exit code ${resumeInfo.exitCode}`;
					const summary =
						summaryText.slice(0, 2000) + (summaryText.length > 2000 ? "\n(truncated, full: session-recap)" : "");
					const meta = [
						resumeInfo.explicitExtensions?.length ? `Compat: ${resumeInfo.explicitExtensions.join(", ")}` : null,
						resumeInfo.warnings?.length ? `Warnings: ${resumeInfo.warnings.join(" | ")}` : null,
					]
						.filter(Boolean)
						.join("\n");

					pi.sendMessage(
						{
							customType: "entwurf-complete",
							content: [
								`${resumeInfo.status === "failed" ? "❌" : "🏁"} resume \`${resumeTaskId}\` (← ${params.taskId}) ${resumeInfo.status} (${analysis.turns} turns, $${analysis.cost.toFixed(4)})`,
								meta || null,
								summary,
							]
								.filter(Boolean)
								.join("\n\n"),
							display: true,
							details: {
								taskId: resumeTaskId,
								originalTaskId: params.taskId,
								status: resumeInfo.status,
								error: resumeInfo.error,
								stopReason: resumeInfo.stopReason,
								explicitExtensions: resumeInfo.explicitExtensions,
								warnings: resumeInfo.warnings,
							},
						},
						{ triggerTurn: true, deliverAs: "followUp" },
					);
				}
			});

			proc.on("error", (err) => {
				resumeInfo.status = "failed";
				resumeInfo.error = err.message;
				resumeInfo.output = err.message;
				delete resumeInfo.proc;
			});

			return {
				content: [
					{
						type: "text",
						text: [
							`🔄 Resume spawned (async)`,
							`Resume ID: ${resumeTaskId}`,
							`Original: ${params.taskId}`,
							`Session: ${sessionFile}`,
							`PID: ${pid}`,
							"",
							"Use entwurf_status to check progress. You'll be notified on completion.",
						].join("\n"),
					},
				],
				details: { taskId: resumeTaskId, originalTaskId: params.taskId, sessionFile, pid },
			};
		},
	});

	// --- /entwurf-status command ---
	pi.registerCommand("entwurf-status", {
		description: "Show status of async entwurfs",
		handler: async (_args, ctx) => {
			if (activeEntwurfs.size === 0) {
				ctx.ui.notify("No active entwurfs.", "info");
				return;
			}
			const lines: string[] = [];
			for (const [id, info] of activeEntwurfs) {
				const alive = info.pid > 0 && isProcessAlive(info.pid);
				if (info.status === "running" && !alive) {
					info.status = "completed";
				}
				if (info.host === "local" && fs.existsSync(info.sessionFile)) {
					const analysis = analyzeSessionFile(info.sessionFile);
					if (analysis.lastModel) info.model = analysis.lastModel;
					info.stopReason = analysis.lastStopReason ?? info.stopReason;
					info.error = analysis.lastError ?? info.error;
					if (!info.error && info.stopReason === "error") {
						info.error = "Entwurf model returned stopReason=error";
					}
					if (info.error || info.stopReason === "error") info.status = "failed";
				}
				const elapsed = Math.round((Date.now() - info.startTime) / 1000);
				const icon = info.status === "running" ? "⏳" : info.status === "completed" ? "✅" : "❌";
				const suffix = info.error ? ` — ${info.error.slice(0, 80)}` : "";
				lines.push(`${icon} ${id} [${info.host}] ${info.status} (${elapsed}s) — ${info.task.slice(0, 60)}${suffix}`);
			}
			ctx.ui.notify(lines.join("\n"), "info");
		},
	});
}
