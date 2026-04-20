import { createHash } from "node:crypto";
import { spawn, type ChildProcessByStdio } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { Readable, Writable } from "node:stream";
import {
	ClientSideConnection,
	PROTOCOL_VERSION,
	type AnyMessage,
	type InitializeResponse,
	type McpServer,
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
export type AcpBackend = "claude" | "codex";

type EnvKvInput = Record<string, string> | Array<{ name: string; value: string }>;

type StdioMcpServerInput = {
	type?: "stdio";
	command: string;
	args?: string[];
	env?: EnvKvInput;
};

type HttpMcpServerInput = {
	type: "http";
	url: string;
	headers?: EnvKvInput;
};

type SseMcpServerInput = {
	type: "sse";
	url: string;
	headers?: EnvKvInput;
};

export type McpServerInput = StdioMcpServerInput | HttpMcpServerInput | SseMcpServerInput;
export type McpServerInputMap = Record<string, McpServerInput>;

export type NormalizedMcpServers = {
	servers: McpServer[];
	hash: string;
	signatureKey: string;
};

export type McpServerConfigIssue = {
	server: string;
	reason: string;
};

export class McpServerConfigError extends Error {
	readonly issues: McpServerConfigIssue[];
	constructor(issues: McpServerConfigIssue[]) {
		const lines = issues.map((issue) => `  - ${issue.server}: ${issue.reason}`).join("\n");
		super(`Invalid piShellAcpProvider.mcpServers:\n${lines}`);
		this.name = "McpServerConfigError";
		this.issues = issues;
	}
}

function validateKvEntries(
	server: string,
	field: "env" | "headers",
	input: unknown,
	issues: McpServerConfigIssue[],
): Array<{ name: string; value: string }> | undefined {
	if (input === undefined) return [];
	const entries: Array<{ name: string; value: string }> = [];
	if (Array.isArray(input)) {
		for (let i = 0; i < input.length; i++) {
			const kv = input[i];
			if (!kv || typeof kv !== "object" || Array.isArray(kv)) {
				issues.push({ server, reason: `"${field}[${i}]" must be an object` });
				return undefined;
			}
			const pair = kv as { name?: unknown; value?: unknown };
			if (typeof pair.name !== "string" || typeof pair.value !== "string") {
				issues.push({ server, reason: `"${field}[${i}]" must have string "name" and "value"` });
				return undefined;
			}
			entries.push({ name: pair.name, value: pair.value });
		}
	} else if (typeof input === "object") {
		for (const [name, value] of Object.entries(input as Record<string, unknown>)) {
			if (typeof value !== "string") {
				issues.push({ server, reason: `"${field}.${name}" must be a string` });
				return undefined;
			}
			entries.push({ name, value });
		}
	} else {
		issues.push({ server, reason: `"${field}" must be an object or array of {name,value}` });
		return undefined;
	}
	entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
	return entries;
}

function normalizeMcpServerEntry(
	name: string,
	raw: unknown,
	issues: McpServerConfigIssue[],
): McpServer | undefined {
	if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
		issues.push({ server: name, reason: "server entry must be an object" });
		return undefined;
	}
	const obj = raw as Record<string, unknown>;
	const declaredType = obj["type"];
	let type: "stdio" | "http" | "sse";
	if (declaredType === undefined) {
		type = "stdio";
	} else if (declaredType === "stdio" || declaredType === "http" || declaredType === "sse") {
		type = declaredType;
	} else {
		issues.push({
			server: name,
			reason: `unsupported "type" ${JSON.stringify(declaredType)} (expected "stdio" | "http" | "sse")`,
		});
		return undefined;
	}

	if (type === "http" || type === "sse") {
		const url = obj["url"];
		if (typeof url !== "string" || url.length === 0) {
			issues.push({ server: name, reason: `${type} server requires non-empty "url"` });
			return undefined;
		}
		const headers = validateKvEntries(name, "headers", obj["headers"], issues);
		if (headers === undefined) return undefined;
		return { type, name, url, headers } as McpServer;
	}

	const command = obj["command"];
	if (typeof command !== "string" || command.length === 0) {
		issues.push({ server: name, reason: `stdio server requires non-empty "command"` });
		return undefined;
	}
	let args: string[] = [];
	if (obj["args"] !== undefined) {
		if (!Array.isArray(obj["args"])) {
			issues.push({ server: name, reason: `"args" must be a string array` });
			return undefined;
		}
		const rawArgs = obj["args"] as unknown[];
		for (let i = 0; i < rawArgs.length; i++) {
			if (typeof rawArgs[i] !== "string") {
				issues.push({ server: name, reason: `"args[${i}]" must be a string` });
				return undefined;
			}
		}
		args = rawArgs as string[];
	}
	const env = validateKvEntries(name, "env", obj["env"], issues);
	if (env === undefined) return undefined;
	return { name, command, args, env } as McpServer;
}

export function normalizeMcpServers(input: McpServerInputMap | undefined): NormalizedMcpServers {
	if (input === undefined || input === null) {
		const empty = "[]";
		return {
			servers: [],
			hash: createHash("sha256").update(empty).digest("hex"),
			signatureKey: empty,
		};
	}
	if (typeof input !== "object" || Array.isArray(input)) {
		throw new McpServerConfigError([
			{
				server: "<root>",
				reason: `mcpServers must be an object (got ${Array.isArray(input) ? "array" : typeof input})`,
			},
		]);
	}
	const issues: McpServerConfigIssue[] = [];
	const names = Object.keys(input).sort();
	const servers: McpServer[] = [];
	for (const name of names) {
		const entry = normalizeMcpServerEntry(name, (input as Record<string, unknown>)[name], issues);
		if (entry) servers.push(entry);
	}
	if (issues.length > 0) {
		throw new McpServerConfigError(issues);
	}
	const signatureKey = JSON.stringify(servers);
	const hash = createHash("sha256").update(signatureKey).digest("hex");
	return { servers, hash, signatureKey };
}

type BridgeSessionCapabilities = {
	loadSession: boolean;
	resumeSession: boolean;
	closeSession: boolean;
};

type AcpLaunchSpec = {
	command: string;
	args: string[];
	source: string;
};

type BackendSessionMetaParams = Pick<EnsureBridgeSessionParams, "modelId" | "settingSources" | "strictMcpConfig">;

type AcpBackendAdapter = {
	id: AcpBackend;
	stderrLabel: string;
	resolveLaunch(): AcpLaunchSpec;
	buildSessionMeta(params: BackendSessionMetaParams, normalizedSystemPrompt: string | undefined): Record<string, any> | undefined;
};

type PersistedBridgeSessionRecord = {
	sessionKey: string;
	acpSessionId: string;
	cwd: string;
	systemPromptAppend?: string | null;
	bridgeConfigSignature: string;
	contextMessageSignatures: string[];
	updatedAt: string;
	version: number;
	provider: string;
};

type CloseBridgeSessionOptions = {
	closeRemote?: boolean;
	invalidatePersisted?: boolean;
};

export type BridgeBootstrapPath = "reuse" | "resume" | "load" | "new";

export type AcpBridgeSession = {
	key: string;
	cwd: string;
	backend: AcpBackend;
	launchSource: string;
	stderrLabel: string;
	child: ChildProcessByStdio<any, any, any>;
	connection: ClientSideConnection;
	initializeResult: InitializeResponse;
	capabilities: BridgeSessionCapabilities;
	acpSessionId: string;
	modelId?: string;
	systemPromptAppend?: string;
	settingSources: ClaudeSettingSource[];
	strictMcpConfig: boolean;
	mcpServers: McpServer[];
	bridgeConfigSignature: string;
	contextMessageSignatures: string[];
	stderrTail: string[];
	closed: boolean;
	bootstrapPath: BridgeBootstrapPath;
	persistedAcpSessionId?: string;
	activePromptHandler?: PendingPromptHandler;
};

export type EnsureBridgeSessionParams = {
	sessionKey: string;
	cwd: string;
	backend: AcpBackend;
	modelId?: string;
	systemPromptAppend?: string;
	settingSources: ClaudeSettingSource[];
	strictMcpConfig: boolean;
	mcpServers: McpServer[];
	bridgeConfigSignature: string;
	contextMessageSignatures: string[];
};

const bridgeSessions = new Map<string, AcpBridgeSession>();
const STDERR_TAIL_MAX_LINES = 120;
const PERSISTED_SESSION_VERSION = 1;
const PERSISTED_SESSION_PROVIDER = "pi-shell-acp";
const SESSION_CACHE_DIR = join(homedir(), ".pi", "agent", "cache", "pi-shell-acp", "sessions");

function normalizeText(text?: string | null): string | undefined {
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

function resolveClaudeAcpLaunch(): AcpLaunchSpec {
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

function resolveCodexAcpLaunch(): AcpLaunchSpec {
	const override = process.env.CODEX_ACP_COMMAND?.trim();
	if (override) {
		return {
			command: "bash",
			args: ["-lc", override],
			source: "env:CODEX_ACP_COMMAND",
		};
	}

	return {
		command: "codex-acp",
		args: [],
		source: "PATH:codex-acp",
	};
}

function buildClaudeSessionMeta(
	params: BackendSessionMetaParams,
	normalizedSystemPrompt: string | undefined,
): Record<string, any> {
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
	if (normalizedSystemPrompt) {
		meta.systemPrompt = { append: normalizedSystemPrompt };
	}
	return meta;
}

const ACP_BACKEND_ADAPTERS: Record<AcpBackend, AcpBackendAdapter> = {
	claude: {
		id: "claude",
		stderrLabel: "claude-agent-acp stderr",
		resolveLaunch: resolveClaudeAcpLaunch,
		buildSessionMeta: buildClaudeSessionMeta,
	},
	codex: {
		id: "codex",
		stderrLabel: "codex-acp stderr",
		resolveLaunch: resolveCodexAcpLaunch,
		buildSessionMeta: () => undefined,
	},
};

export function resolveAcpBackendAdapter(backend: AcpBackend): AcpBackendAdapter {
	return ACP_BACKEND_ADAPTERS[backend];
}

export function resolveAcpBackendLaunch(backend: AcpBackend): AcpLaunchSpec {
	return resolveAcpBackendAdapter(backend).resolveLaunch();
}

export function buildSessionMetaForBackend(
	backend: AcpBackend,
	params: BackendSessionMetaParams,
	normalizedSystemPrompt: string | undefined,
): Record<string, any> | undefined {
	return resolveAcpBackendAdapter(backend).buildSessionMeta(params, normalizedSystemPrompt);
}

function hasPrefix<T>(prefix: T[], value: T[]): boolean {
	if (prefix.length > value.length) return false;
	for (let i = 0; i < prefix.length; i++) {
		if (prefix[i] !== value[i]) return false;
	}
	return true;
}

function isPersistableSessionKey(sessionKey: string): boolean {
	return sessionKey.startsWith("pi:");
}

function getPersistedSessionPath(sessionKey: string): string {
	const digest = createHash("sha256").update(sessionKey).digest("hex");
	return join(SESSION_CACHE_DIR, `${digest}.json`);
}

function isNonEmptyString(value: unknown): value is string {
	return typeof value === "string" && value.length > 0;
}

function isStringArray(value: unknown): value is string[] {
	return Array.isArray(value) && value.every((item) => typeof item === "string");
}

function deletePersistedSessionRecord(sessionKey: string): void {
	if (!isPersistableSessionKey(sessionKey)) return;
	rmSync(getPersistedSessionPath(sessionKey), { force: true });
}

function parsePersistedSessionRecord(raw: unknown, sessionKey: string): PersistedBridgeSessionRecord | undefined {
	if (!raw || typeof raw !== "object") return undefined;
	const record = raw as Record<string, unknown>;
	if (record["version"] !== PERSISTED_SESSION_VERSION) return undefined;
	if (record["provider"] !== PERSISTED_SESSION_PROVIDER) return undefined;
	if (record["sessionKey"] !== sessionKey) return undefined;
	if (!isNonEmptyString(record["acpSessionId"])) return undefined;
	if (!isNonEmptyString(record["cwd"])) return undefined;
	if (!isNonEmptyString(record["bridgeConfigSignature"])) return undefined;
	if (!isStringArray(record["contextMessageSignatures"])) return undefined;
	if (!isNonEmptyString(record["updatedAt"])) return undefined;
	const systemPromptAppend = record["systemPromptAppend"];
	if (!(systemPromptAppend == null || typeof systemPromptAppend === "string")) return undefined;
	return {
		sessionKey,
		acpSessionId: record["acpSessionId"] as string,
		cwd: record["cwd"] as string,
		systemPromptAppend: (systemPromptAppend ?? null) as string | null,
		bridgeConfigSignature: record["bridgeConfigSignature"] as string,
		contextMessageSignatures: [...(record["contextMessageSignatures"] as string[])],
		updatedAt: record["updatedAt"] as string,
		version: PERSISTED_SESSION_VERSION,
		provider: PERSISTED_SESSION_PROVIDER,
	};
}

function readPersistedSessionRecord(sessionKey: string): PersistedBridgeSessionRecord | undefined {
	if (!isPersistableSessionKey(sessionKey)) return undefined;
	const filePath = getPersistedSessionPath(sessionKey);
	if (!existsSync(filePath)) return undefined;
	try {
		const parsed = JSON.parse(readFileSync(filePath, "utf8")) as unknown;
		const record = parsePersistedSessionRecord(parsed, sessionKey);
		if (!record) {
			deletePersistedSessionRecord(sessionKey);
			return undefined;
		}
		return record;
	} catch {
		deletePersistedSessionRecord(sessionKey);
		return undefined;
	}
}

function persistBridgeSessionRecord(session: AcpBridgeSession): void {
	if (!isPersistableSessionKey(session.key)) return;
	mkdirSync(SESSION_CACHE_DIR, { recursive: true });
	const record: PersistedBridgeSessionRecord = {
		sessionKey: session.key,
		acpSessionId: session.acpSessionId,
		cwd: session.cwd,
		systemPromptAppend: session.systemPromptAppend ?? null,
		bridgeConfigSignature: session.bridgeConfigSignature,
		contextMessageSignatures: [...session.contextMessageSignatures],
		updatedAt: new Date().toISOString(),
		version: PERSISTED_SESSION_VERSION,
		provider: PERSISTED_SESSION_PROVIDER,
	};
	writeFileSync(getPersistedSessionPath(session.key), `${JSON.stringify(record, null, 2)}\n`);
}

function capabilityEnabled(value: unknown): boolean {
	return value === true || (!!value && typeof value === "object");
}

function detectSessionCapabilities(initializeResult: InitializeResponse): BridgeSessionCapabilities {
	const topLevel = initializeResult as any;
	const nestedAgentCapabilities = topLevel?.agentCapabilities;
	const nestedSessionCapabilities = nestedAgentCapabilities?.sessionCapabilities;
	const topLevelSessionCapabilities = topLevel?.sessionCapabilities;
	const nestedSession = nestedAgentCapabilities?.session;
	const topLevelSession = topLevel?.session;
	return {
		loadSession: nestedAgentCapabilities?.loadSession === true || topLevel?.loadSession === true,
		resumeSession:
			capabilityEnabled(nestedSessionCapabilities?.resume) ||
			capabilityEnabled(topLevelSessionCapabilities?.resume) ||
			capabilityEnabled(nestedSession?.resume) ||
			capabilityEnabled(topLevelSession?.resume),
		closeSession:
			capabilityEnabled(nestedSessionCapabilities?.close) ||
			capabilityEnabled(topLevelSessionCapabilities?.close) ||
			capabilityEnabled(nestedSession?.close) ||
			capabilityEnabled(topLevelSession?.close),
	};
}

function isSessionCompatible(
	session: Pick<AcpBridgeSession, "cwd" | "backend" | "systemPromptAppend" | "bridgeConfigSignature" | "contextMessageSignatures">,
	params: EnsureBridgeSessionParams,
	normalizedSystemPrompt: string | undefined,
): boolean {
	return (
		session.cwd === params.cwd &&
		session.backend === params.backend &&
		session.systemPromptAppend === normalizedSystemPrompt &&
		session.bridgeConfigSignature === params.bridgeConfigSignature &&
		hasPrefix(session.contextMessageSignatures, params.contextMessageSignatures)
	);
}

function isPersistedSessionCompatible(
	record: PersistedBridgeSessionRecord,
	params: EnsureBridgeSessionParams,
	normalizedSystemPrompt: string | undefined,
): boolean {
	return (
		record.cwd === params.cwd &&
		normalizeText(record.systemPromptAppend) === normalizedSystemPrompt &&
		record.bridgeConfigSignature === params.bridgeConfigSignature &&
		hasPrefix(record.contextMessageSignatures, params.contextMessageSignatures)
	);
}

function buildSessionMeta(params: EnsureBridgeSessionParams, normalizedSystemPrompt: string | undefined): Record<string, any> | undefined {
	return buildSessionMetaForBackend(params.backend, params, normalizedSystemPrompt);
}

function resolveModelIdFromSessionResponse(response: any, fallback?: string): string | undefined {
	const currentModelId = response?.models?.currentModelId;
	return typeof currentModelId === "string" && currentModelId.length > 0 ? currentModelId : fallback;
}

async function enforceRequestedSessionModel(
	session: AcpBridgeSession,
	requestedModelId: string | undefined,
): Promise<void> {
	if (!requestedModelId) return;
	const setModel = (session.connection as any).unstable_setSessionModel;
	if (typeof setModel !== "function") return;
	await setModel.call(session.connection, {
		sessionId: session.acpSessionId,
		modelId: requestedModelId,
	});
	session.modelId = requestedModelId;
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

async function destroyBridgeSession(
	session: AcpBridgeSession,
	options: Required<CloseBridgeSessionOptions>,
): Promise<void> {
	if (bridgeSessions.get(session.key) === session) {
		bridgeSessions.delete(session.key);
	}
	session.closed = true;
	session.activePromptHandler = undefined;
	if (options.invalidatePersisted) {
		deletePersistedSessionRecord(session.key);
	}
	if (options.closeRemote && session.capabilities.closeSession && session.acpSessionId) {
		try {
			await (session.connection as any).unstable_closeSession?.({ sessionId: session.acpSessionId });
		} catch {
			// ignore
		}
	}
	killProcessTree(session.child);
}

async function createBridgeProcess(params: EnsureBridgeSessionParams): Promise<AcpBridgeSession> {
	const adapter = resolveAcpBackendAdapter(params.backend);
	const launch = adapter.resolveLaunch();
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
				throw new Error("Client-side writeTextFile is not supported in pi-shell-acp ACP mode.");
			},
		}),
		transport,
	);

	session = {
		key: params.sessionKey,
		cwd: params.cwd,
		backend: params.backend,
		launchSource: launch.source,
		stderrLabel: adapter.stderrLabel,
		child,
		connection,
		initializeResult: undefined as any,
		capabilities: {
			loadSession: false,
			resumeSession: false,
			closeSession: false,
		},
		acpSessionId: "",
		modelId: params.modelId,
		systemPromptAppend: normalizeText(params.systemPromptAppend),
		settingSources: [...params.settingSources],
		strictMcpConfig: params.strictMcpConfig,
		mcpServers: [...params.mcpServers],
		bridgeConfigSignature: params.bridgeConfigSignature,
		contextMessageSignatures: [...params.contextMessageSignatures],
		stderrTail,
		closed: false,
		bootstrapPath: "new",
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
			name: "pi-shell-acp",
			version: "2.0.0-acp",
		},
	});
	session.initializeResult = initializeResult;
	session.capabilities = detectSessionCapabilities(initializeResult);
	return session;
}

async function startNewBridgeSession(params: EnsureBridgeSessionParams): Promise<AcpBridgeSession> {
	const session = await createBridgeProcess(params);
	try {
		const meta = buildSessionMeta(params, session.systemPromptAppend);
		const created = await session.connection.newSession({
			cwd: params.cwd,
			mcpServers: [...params.mcpServers],
			...(meta ? { _meta: meta } : {}),
		});
		if (!created?.sessionId) {
			throw new Error(`ACP newSession returned no sessionId (${session.launchSource})`);
		}
		session.acpSessionId = created.sessionId;
		session.modelId = resolveModelIdFromSessionResponse(created, params.modelId);
		session.bootstrapPath = "new";
		await enforceRequestedSessionModel(session, params.modelId);
		bridgeSessions.set(params.sessionKey, session);
		persistBridgeSessionRecord(session);
		return session;
	} catch (error) {
		await destroyBridgeSession(session, {
			closeRemote: false,
			invalidatePersisted: false,
		});
		throw error;
	}
}

async function bootstrapPersistedBridgeSession(
	params: EnsureBridgeSessionParams,
	record: PersistedBridgeSessionRecord,
): Promise<AcpBridgeSession> {
	const session = await createBridgeProcess(params);
	const meta = buildSessionMeta(params, session.systemPromptAppend);
	let shouldInvalidatePersisted = false;
	try {
		if (session.capabilities.resumeSession) {
			try {
				const resumed = await (session.connection as any).unstable_resumeSession({
					sessionId: record.acpSessionId,
					cwd: params.cwd,
					mcpServers: [...params.mcpServers],
					...(meta ? { _meta: meta } : {}),
				});
				session.acpSessionId = record.acpSessionId;
				session.modelId = resolveModelIdFromSessionResponse(resumed, params.modelId);
				session.bootstrapPath = "resume";
				session.persistedAcpSessionId = record.acpSessionId;
				await enforceRequestedSessionModel(session, params.modelId);
				bridgeSessions.set(params.sessionKey, session);
				persistBridgeSessionRecord(session);
				return session;
			} catch {
				shouldInvalidatePersisted = true;
			}
		}

		if (session.capabilities.loadSession) {
			try {
				const loaded = await session.connection.loadSession({
					sessionId: record.acpSessionId,
					cwd: params.cwd,
					mcpServers: [...params.mcpServers],
					...(meta ? { _meta: meta } : {}),
				});
				session.acpSessionId = record.acpSessionId;
				session.modelId = resolveModelIdFromSessionResponse(loaded, params.modelId);
				session.bootstrapPath = "load";
				session.persistedAcpSessionId = record.acpSessionId;
				await enforceRequestedSessionModel(session, params.modelId);
				bridgeSessions.set(params.sessionKey, session);
				persistBridgeSessionRecord(session);
				return session;
			} catch {
				shouldInvalidatePersisted = true;
			}
		}

		if (shouldInvalidatePersisted) {
			deletePersistedSessionRecord(params.sessionKey);
		}

		const created = await session.connection.newSession({
			cwd: params.cwd,
			mcpServers: [...params.mcpServers],
			...(meta ? { _meta: meta } : {}),
		});
		if (!created?.sessionId) {
			throw new Error(`ACP newSession returned no sessionId (${session.launchSource})`);
		}
		session.acpSessionId = created.sessionId;
		session.modelId = resolveModelIdFromSessionResponse(created, params.modelId);
		session.bootstrapPath = "new";
		session.persistedAcpSessionId = shouldInvalidatePersisted ? record.acpSessionId : undefined;
		await enforceRequestedSessionModel(session, params.modelId);
		bridgeSessions.set(params.sessionKey, session);
		persistBridgeSessionRecord(session);
		return session;
	} catch (error) {
		await destroyBridgeSession(session, {
			closeRemote: false,
			invalidatePersisted: false,
		});
		throw error;
	}
}

export async function ensureBridgeSession(params: EnsureBridgeSessionParams): Promise<AcpBridgeSession> {
	const normalizedSystemPrompt = normalizeText(params.systemPromptAppend);
	const normalizedParams: EnsureBridgeSessionParams = {
		...params,
		systemPromptAppend: normalizedSystemPrompt,
	};
	const existing = bridgeSessions.get(params.sessionKey);
	const existingCompatible = existing
		? isSessionCompatible(existing, normalizedParams, normalizedSystemPrompt)
		: false;
	if (existing && existingCompatible && !existing.closed && isChildAlive(existing.child)) {
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
				return await startNewBridgeSession(normalizedParams);
			}
		}
		existing.settingSources = [...params.settingSources];
		existing.strictMcpConfig = params.strictMcpConfig;
		existing.bridgeConfigSignature = params.bridgeConfigSignature;
		existing.contextMessageSignatures = [...params.contextMessageSignatures];
		existing.bootstrapPath = "reuse";
		persistBridgeSessionRecord(existing);
		return existing;
	}

	if (existing) {
		await closeBridgeSession(params.sessionKey, {
			closeRemote: isChildAlive(existing.child),
			invalidatePersisted: !existingCompatible,
		});
	}

	const persisted = readPersistedSessionRecord(params.sessionKey);
	if (persisted) {
		if (!isPersistedSessionCompatible(persisted, normalizedParams, normalizedSystemPrompt)) {
			deletePersistedSessionRecord(params.sessionKey);
		} else {
			return await bootstrapPersistedBridgeSession(normalizedParams, persisted);
		}
	}

	return await startNewBridgeSession(normalizedParams);
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

export async function closeBridgeSession(
	sessionKey: string,
	options: CloseBridgeSessionOptions = {},
): Promise<void> {
	const session = bridgeSessions.get(sessionKey);
	if (!session) {
		if (options.invalidatePersisted !== false) {
			deletePersistedSessionRecord(sessionKey);
		}
		return;
	}
	await destroyBridgeSession(session, {
		closeRemote: options.closeRemote ?? true,
		invalidatePersisted: options.invalidatePersisted ?? true,
	});
}

export async function cleanupBridgeSessionProcess(sessionKey: string): Promise<void> {
	await closeBridgeSession(sessionKey, {
		closeRemote: false,
		invalidatePersisted: false,
	});
}

export function describeBridgeSession(session: AcpBridgeSession): Record<string, unknown> {
	return {
		sessionKey: session.key,
		cwd: session.cwd,
		bootstrapPath: session.bootstrapPath,
		acpSessionId: session.acpSessionId,
		persistedAcpSessionId: session.persistedAcpSessionId,
		backend: session.backend,
		launchSource: session.launchSource,
		modelId: session.modelId,
		capabilities: {
			resumeSession: session.capabilities.resumeSession,
			loadSession: session.capabilities.loadSession,
			closeSession: session.capabilities.closeSession,
		},
	};
}

export function getBridgeErrorDetails(error: unknown, session?: AcpBridgeSession): string {
	const message = error instanceof Error ? error.message : String(error);
	const diagnostic = session ? `\n\n[pi-shell-acp session]\n${JSON.stringify(describeBridgeSession(session), null, 2)}` : "";
	const stderrTail = session?.stderrTail?.slice(-20)?.join("\n");
	const stderrBlock = stderrTail ? `\n\n[${session?.stderrLabel ?? "acp stderr"}]\n${stderrTail}` : "";
	return `${message}${diagnostic}${stderrBlock}`;
}
