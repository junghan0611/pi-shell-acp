import { spawn, type ChildProcessByStdio } from "node:child_process";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { Readable, Writable } from "node:stream";
import {
	ClientSideConnection,
	PROTOCOL_VERSION,
	type AnyMessage,
	type InitializeResponse,
	type PromptResponse,
	type RequestPermissionRequest,
	type RequestPermissionResponse,
	type SessionNotification,
} from "@agentclientprotocol/sdk";

type PromptContentBlock =
	| { type: "text"; text: string }
	| { type: "image"; data?: string; mimeType?: string; uri?: string };

export type BridgePromptEvent =
	| { type: "session_notification"; notification: SessionNotification }
	| {
		type: "permission_request";
		request: RequestPermissionRequest;
		response: RequestPermissionResponse;
	  };

type PendingPromptHandler = (event: BridgePromptEvent) => Promise<void> | void;

export type ClaudeSettingSource = "user" | "project" | "local";

export type AcpBridgeSession = {
	key: string;
	cwd: string;
	child: ChildProcessByStdio<any, any, any>;
	connection: ClientSideConnection;
	initializeResult: InitializeResponse;
	acpSessionId: string;
	modelId?: string;
	systemPromptAppend?: string;
	settingSources: ClaudeSettingSource[];
	strictMcpConfig: boolean;
	bridgeConfigSignature: string;
	contextMessageSignatures: string[];
	stderrTail: string[];
	closed: boolean;
	activePromptHandler?: PendingPromptHandler;
};

export type EnsureBridgeSessionParams = {
	sessionKey: string;
	cwd: string;
	modelId?: string;
	systemPromptAppend?: string;
	settingSources: ClaudeSettingSource[];
	strictMcpConfig: boolean;
	bridgeConfigSignature: string;
	contextMessageSignatures: string[];
};

const bridgeSessions = new Map<string, AcpBridgeSession>();
const STDERR_TAIL_MAX_LINES = 120;

function normalizeText(text?: string): string | undefined {
	const trimmed = text?.trim();
	return trimmed ? trimmed : undefined;
}

function isChildAlive(child?: ChildProcessByStdio<any, any, any>): boolean {
	if (!child) return false;
	return child.exitCode == null && child.signalCode == null && !child.killed;
}

function appendStderrTail(target: string[], chunk: Buffer | string): void {
	const text = typeof chunk === "string" ? chunk : chunk.toString("utf8");
	for (const line of text.split(/\r?\n/)) {
		if (!line) continue;
		target.push(line);
	}
	while (target.length > STDERR_TAIL_MAX_LINES) {
		target.shift();
	}
}

function createNdJsonMessageStream(
	stdinWritable: WritableStream<Uint8Array>,
	stdoutReadable: ReadableStream<Uint8Array>,
): {
	readable: ReadableStream<AnyMessage>;
	writable: WritableStream<AnyMessage>;
} {
	const encoder = new TextEncoder();
	const decoder = new TextDecoder();

	const readable = new ReadableStream<AnyMessage>({
		async start(controller) {
			let buffered = "";
			const reader = stdoutReadable.getReader();
			try {
				while (true) {
					const { value, done } = await reader.read();
					if (done) break;
					if (!value) continue;
					buffered += decoder.decode(value, { stream: true });
					const lines = buffered.split("\n");
					buffered = lines.pop() ?? "";
					for (const line of lines) {
						const trimmed = line.trim();
						if (!trimmed) continue;
						try {
							controller.enqueue(JSON.parse(trimmed) as AnyMessage);
						} catch {
							// claude-agent-acp logs to stderr, but ignore stray non-JSON stdout defensively.
						}
					}
				}
				const tail = buffered.trim();
				if (tail) {
					try {
						controller.enqueue(JSON.parse(tail) as AnyMessage);
					} catch {
						// ignore
					}
				}
			} finally {
				reader.releaseLock();
				controller.close();
			}
		},
	});

	const writable = new WritableStream<AnyMessage>({
		async write(message) {
			const writer = stdinWritable.getWriter();
			try {
				await writer.write(encoder.encode(`${JSON.stringify(message)}\n`));
			} finally {
				writer.releaseLock();
			}
		},
	});

	return { readable, writable };
}

function pickOption(options: Array<{ optionId: string; kind?: string }>, kinds: string[]): string | undefined {
	for (const kind of kinds) {
		const match = options.find((option) => option.kind === kind);
		if (match?.optionId) return match.optionId;
	}
	return undefined;
}

function inferPermissionKind(params: RequestPermissionRequest): string | undefined {
	const explicitKind = (params as any)?.toolCall?.kind;
	if (typeof explicitKind === "string" && explicitKind.length > 0) return explicitKind;
	const title = String((params as any)?.toolCall?.title ?? "").toLowerCase();
	if (!title) return undefined;
	if (title.includes("read") || title.includes("cat")) return "read";
	if (title.includes("search") || title.includes("grep") || title.includes("find")) return "search";
	if (title.includes("edit") || title.includes("write") || title.includes("patch")) return "edit";
	if (title.includes("delete") || title.includes("remove")) return "delete";
	if (title.includes("move") || title.includes("rename")) return "move";
	if (title.includes("run") || title.includes("bash") || title.includes("execute")) return "execute";
	return "other";
}

function resolvePermissionResponse(params: RequestPermissionRequest): RequestPermissionResponse {
	const mode = (process.env.CLAUDE_ACP_PERMISSION_MODE ?? "approve-all").trim().toLowerCase();
	const options = Array.isArray((params as any)?.options) ? ((params as any).options as Array<{ optionId: string; kind?: string }>) : [];
	if (options.length === 0) {
		return { outcome: { outcome: "cancelled" } };
	}

	const allowOptionId = pickOption(options, ["allow_once", "allow_always"]);
	const rejectOptionId = pickOption(options, ["reject_once", "reject_always"]);
	const kind = inferPermissionKind(params);

	if (mode === "deny-all") {
		return rejectOptionId
			? { outcome: { outcome: "selected", optionId: rejectOptionId } }
			: { outcome: { outcome: "cancelled" } };
	}

	if (mode === "approve-reads" && kind !== "read" && kind !== "search") {
		return rejectOptionId
			? { outcome: { outcome: "selected", optionId: rejectOptionId } }
			: { outcome: { outcome: "cancelled" } };
	}

	if (allowOptionId) {
		return { outcome: { outcome: "selected", optionId: allowOptionId } };
	}

	return { outcome: { outcome: "selected", optionId: options[0].optionId } };
}

function resolveClaudeAcpLaunch(): { command: string; args: string[]; source: string } {
	const override = process.env.CLAUDE_AGENT_ACP_COMMAND?.trim();
	if (override) {
		return {
			command: "bash",
			args: ["-lc", override],
			source: "env:CLAUDE_AGENT_ACP_COMMAND",
		};
	}

	const require = createRequire(import.meta.url);
	try {
		const packageJsonPath = require.resolve("@agentclientprotocol/claude-agent-acp/package.json");
		const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8")) as {
			bin?: string | Record<string, string>;
		};
		const binPath =
			typeof packageJson.bin === "string"
				? packageJson.bin
				: packageJson.bin?.["claude-agent-acp"];
		if (binPath) {
			return {
				command: process.execPath,
				args: [join(dirname(packageJsonPath), binPath)],
				source: "package:@agentclientprotocol/claude-agent-acp",
			};
		}
	} catch {
		// fall through
	}

	return {
		command: "claude-agent-acp",
		args: [],
		source: "PATH:claude-agent-acp",
	};
}

function hasPrefix<T>(prefix: T[], value: T[]): boolean {
	if (prefix.length > value.length) return false;
	for (let i = 0; i < prefix.length; i++) {
		if (prefix[i] !== value[i]) return false;
	}
	return true;
}

function killProcessTree(child: ChildProcessByStdio<any, any, any>): void {
	const pid = child.pid;
	if (!pid) return;
	if (process.platform !== "win32") {
		try {
			process.kill(-pid, "SIGTERM");
			setTimeout(() => {
				try {
					process.kill(-pid, "SIGKILL");
				} catch {
					// ignore
				}
			}, 1500).unref();
			return;
		} catch {
			// fall through to direct kill
		}
	}
	try {
		child.kill("SIGTERM");
	} catch {
		// ignore
	}
}

async function startBridgeSession(params: EnsureBridgeSessionParams): Promise<AcpBridgeSession> {
	const launch = resolveClaudeAcpLaunch();
	const child = spawn(launch.command, launch.args, {
		cwd: params.cwd,
		env: process.env,
		stdio: ["pipe", "pipe", "pipe"],
		detached: process.platform !== "win32",
	});

	const stderrTail: string[] = [];
	child.stderr.on("data", (chunk) => appendStderrTail(stderrTail, chunk));

	const stdoutReadable = Readable.toWeb(child.stdout) as ReadableStream<Uint8Array>;
	const stdinWritable = Writable.toWeb(child.stdin);
	const transport = createNdJsonMessageStream(stdinWritable, stdoutReadable);

	let session: AcpBridgeSession;
	const connection = new ClientSideConnection(
		() => ({
			sessionUpdate: async (notification: SessionNotification) => {
				await session.activePromptHandler?.({
					type: "session_notification",
					notification,
				});
			},
			requestPermission: async (request: RequestPermissionRequest): Promise<RequestPermissionResponse> => {
				const response = resolvePermissionResponse(request);
				await session.activePromptHandler?.({
					type: "permission_request",
					request,
					response,
				});
				return response;
			},
			readTextFile: async (request: any): Promise<any> => {
				const content = readFileSync(request.path, "utf8");
				return { content };
			},
			writeTextFile: async (): Promise<any> => {
				throw new Error("Client-side writeTextFile is not supported in claude-agent-sdk-pi ACP mode.");
			},
		}),
		transport,
	);

	session = {
		key: params.sessionKey,
		cwd: params.cwd,
		child,
		connection,
		initializeResult: undefined as any,
		acpSessionId: "",
		modelId: params.modelId,
		systemPromptAppend: normalizeText(params.systemPromptAppend),
		settingSources: [...params.settingSources],
		strictMcpConfig: params.strictMcpConfig,
		bridgeConfigSignature: params.bridgeConfigSignature,
		contextMessageSignatures: [...params.contextMessageSignatures],
		stderrTail,
		closed: false,
	};

	child.once("exit", () => {
		session.closed = true;
		if (bridgeSessions.get(session.key) === session) {
			bridgeSessions.delete(session.key);
		}
	});
	child.once("error", () => {
		session.closed = true;
		if (bridgeSessions.get(session.key) === session) {
			bridgeSessions.delete(session.key);
		}
	});

	const initializeResult = await connection.initialize({
		protocolVersion: PROTOCOL_VERSION,
		clientCapabilities: {},
		clientInfo: {
			name: "claude-agent-sdk-pi",
			version: "2.0.0-acp",
		},
	});
	session.initializeResult = initializeResult;

	const claudeCodeOptions: Record<string, any> = {
		...(params.modelId ? { model: params.modelId } : {}),
		tools: { type: "preset", preset: "claude_code" },
		settingSources: [...params.settingSources],
	};
	if (params.strictMcpConfig) {
		claudeCodeOptions.extraArgs = {
			...(claudeCodeOptions.extraArgs ?? {}),
			"strict-mcp-config": null,
		};
	}

	const meta: Record<string, any> = {
		claudeCode: {
			options: claudeCodeOptions,
		},
	};
	if (session.systemPromptAppend) {
		meta.systemPrompt = { append: session.systemPromptAppend };
	}

	const created = await connection.newSession({
		cwd: params.cwd,
		mcpServers: [],
		_meta: meta,
	});
	if (!created?.sessionId) {
		throw new Error(`ACP newSession returned no sessionId (${launch.source})`);
	}
	session.acpSessionId = created.sessionId;
	bridgeSessions.set(params.sessionKey, session);
	return session;
}

export async function ensureBridgeSession(params: EnsureBridgeSessionParams): Promise<AcpBridgeSession> {
	const normalizedSystemPrompt = normalizeText(params.systemPromptAppend);
	const existing = bridgeSessions.get(params.sessionKey);
	if (
		existing &&
		!existing.closed &&
		isChildAlive(existing.child) &&
		existing.cwd === params.cwd &&
		existing.systemPromptAppend === normalizedSystemPrompt &&
		existing.bridgeConfigSignature === params.bridgeConfigSignature &&
		hasPrefix(existing.contextMessageSignatures, params.contextMessageSignatures)
	) {
		if (params.modelId && existing.modelId !== params.modelId) {
			const setModel = (existing.connection as any).unstable_setSessionModel;
			if (typeof setModel === "function") {
				await setModel.call(existing.connection, {
					sessionId: existing.acpSessionId,
					modelId: params.modelId,
				});
				existing.modelId = params.modelId;
			} else {
				await closeBridgeSession(params.sessionKey);
				return await startBridgeSession({
					...params,
					systemPromptAppend: normalizedSystemPrompt,
				});
			}
		}
		existing.settingSources = [...params.settingSources];
		existing.strictMcpConfig = params.strictMcpConfig;
		existing.bridgeConfigSignature = params.bridgeConfigSignature;
		existing.contextMessageSignatures = [...params.contextMessageSignatures];
		return existing;
	}

	if (existing) {
		await closeBridgeSession(params.sessionKey);
	}

	return await startBridgeSession({
		...params,
		systemPromptAppend: normalizedSystemPrompt,
	});
}

export function setActivePromptHandler(
	session: AcpBridgeSession,
	handler: PendingPromptHandler | undefined,
): void {
	session.activePromptHandler = handler;
}

export async function sendPrompt(
	session: AcpBridgeSession,
	prompt: PromptContentBlock[],
): Promise<PromptResponse> {
	return await (session.connection as any).prompt({
		sessionId: session.acpSessionId,
		prompt,
	});
}

export async function cancelActivePrompt(session: AcpBridgeSession): Promise<void> {
	await (session.connection as any).cancel?.({ sessionId: session.acpSessionId });
}

export async function closeBridgeSession(sessionKey: string): Promise<void> {
	const session = bridgeSessions.get(sessionKey);
	if (!session) return;
	bridgeSessions.delete(sessionKey);
	session.closed = true;
	session.activePromptHandler = undefined;
	try {
		await (session.connection as any).unstable_closeSession?.({ sessionId: session.acpSessionId });
	} catch {
		// ignore
	}
	killProcessTree(session.child);
}

export function getBridgeErrorDetails(error: unknown, session?: AcpBridgeSession): string {
	const message = error instanceof Error ? error.message : String(error);
	const stderrTail = session?.stderrTail?.slice(-20)?.join("\n");
	return stderrTail ? `${message}\n\n[claude-agent-acp stderr]\n${stderrTail}` : message;
}
