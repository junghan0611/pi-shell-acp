import { type ChildProcessByStdio, execFileSync, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import {
	existsSync,
	lstatSync,
	mkdirSync,
	readdirSync,
	readFileSync,
	readlinkSync,
	rmSync,
	symlinkSync,
	unlinkSync,
	writeFileSync,
} from "node:fs";
import { createRequire } from "node:module";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { Readable, Writable } from "node:stream";
import {
	type AnyMessage,
	ClientSideConnection,
	type InitializeResponse,
	type McpServer,
	PROTOCOL_VERSION,
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

function normalizeMcpServerEntry(name: string, raw: unknown, issues: McpServerConfigIssue[]): McpServer | undefined {
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

type BackendSessionMetaParams = Pick<
	EnsureBridgeSessionParams,
	"modelId" | "settingSources" | "strictMcpConfig" | "tools" | "skillPlugins" | "permissionAllow" | "disallowedTools"
>;

type AcpBackendAdapter = {
	id: AcpBackend;
	stderrLabel: string;
	resolveLaunch(): AcpLaunchSpec;
	buildSessionMeta(
		params: BackendSessionMetaParams,
		normalizedSystemPrompt: string | undefined,
	): Record<string, any> | undefined;
	/**
	 * Optional: turn a bootstrap-time augmentation string (e.g. the rendered
	 * engraving) into ContentBlocks that should be prepended to the FIRST
	 * prompt sent to a freshly-opened ACP session. Used for backends without
	 * a _meta.systemPrompt.append style extension (e.g. Codex ACP), so that
	 * this repo can still deliver identity context across ACP peers that only
	 * accept the spec-baseline ContentBlock carrier. Return undefined to skip.
	 */
	buildBootstrapPromptAugment?(augmentText: string): PromptContentBlock[] | undefined;
	/**
	 * Optional: backend-specific environment variable defaults injected into
	 * the spawned child process. process.env values win on conflict so the
	 * operator can always override from their shell. Used to enforce
	 * bridge-level safety defaults the backend wouldn't pick up on its own
	 * (e.g. disabling Claude Code's built-in auto-compaction so pi remains
	 * the single context-management authority).
	 */
	bridgeEnvDefaults?: Record<string, string>;
};

type PersistedBridgeSessionRecord = {
	sessionKey: string;
	acpSessionId: string;
	cwd: string;
	systemPromptAppend?: string | null;
	bootstrapPromptAugment?: string | null;
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
	/** Normalized augment string routed via adapter.buildBootstrapPromptAugment on the first prompt of a bootstrapPath="new" session. */
	bootstrapPromptAugment?: string;
	/** ContentBlocks to prepend to the NEXT sendPrompt call, then cleared. Populated on new-session bootstrap for backends whose adapter implements buildBootstrapPromptAugment. */
	bootstrapPromptAugmentPending?: PromptContentBlock[];
	settingSources: ClaudeSettingSource[];
	strictMcpConfig: boolean;
	mcpServers: McpServer[];
	tools: string[];
	skillPlugins: string[];
	permissionAllow: string[];
	disallowedTools: string[];
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
	/** Augmentation text delivered to the backend on the first prompt of a new session via adapter.buildBootstrapPromptAugment — typically the rendered engraving for backends without a systemPromptAppend extension (e.g. Codex). */
	bootstrapPromptAugment?: string;
	settingSources: ClaudeSettingSource[];
	strictMcpConfig: boolean;
	mcpServers: McpServer[];
	/** Built-in Claude Code tools to expose. Defaults to pi baseline (Read/Bash/Edit/Write) so the system prompt's advertised tools and the SDK's actual tool surface match. */
	tools: string[];
	/** Absolute paths to Claude Code plugin directories injected via SDK `plugins: [{type:"local", path}]`. Used to deliver skills explicitly without opening up `~/.claude/skills/` via settingSources. */
	skillPlugins: string[];
	/** Wildcard rules passed to the SDK as `Options.settings.permissions.allow`. Combined with the user's `~/.claude/settings.json` `defaultMode` (resolved by claude-agent-acp), this gives explicit YOLO without flipping the user's native default mode. */
	permissionAllow: string[];
	/** Tool names passed to the SDK as `Options.disallowedTools`. Used to suppress the SDK's deferred-tool advertisement (Cron+Task+Worktree+PlanMode families plus WebFetch, WebSearch, Monitor, PushNotification, RemoteTrigger, NotebookEdit, AskUserQuestion) so the agent's awareness of available tools stays inside pi's declared baseline. claude-agent-acp merges its own ["AskUserQuestion"] default with this list. */
	disallowedTools: string[];
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
	const options = Array.isArray((params as any)?.options)
		? ((params as any).options as Array<{ optionId: string; kind?: string }>)
		: [];
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
		const binPath = typeof packageJson.bin === "string" ? packageJson.bin : packageJson.bin?.["claude-agent-acp"];
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

const CODEX_DISABLE_AUTO_COMPACT_ARGS = ["-c", "model_auto_compact_token_limit=9223372036854775807"] as const;

// codex-rs approval/sandbox preset table — kebab-case ids match
// codex-utils-approval-presets builtin_approval_presets() so the same
// vocabulary works on both sides of the bridge. We default to `full-access`
// for parity with pi-shell-acp's pi-YOLO model on the Claude side
// (permissionAllow wildcards, no auto-compaction). It is also the only
// codex preset that lets workspace-external files (e.g. ~/.gnupg/ which
// gogcli reads to decrypt tokens) come through, so pi-baseline skills
// continue to work without piecewise sandbox carve-outs.
//
// Operators who prefer a tighter default can opt in via
// PI_SHELL_ACP_CODEX_MODE=auto (codex-rs's own default — workspace-write
// sandbox, on-request approvals) or =read-only.
export type CodexMode = "read-only" | "auto" | "full-access";

const DEFAULT_CODEX_MODE: CodexMode = "full-access";

const CODEX_MODE_ARGS: Record<CodexMode, readonly string[]> = {
	"read-only": ["-c", "approval_policy=on-request", "-c", "sandbox_mode=read-only"],
	auto: ["-c", "approval_policy=on-request", "-c", "sandbox_mode=workspace-write"],
	"full-access": ["-c", "approval_policy=never", "-c", "sandbox_mode=danger-full-access"],
};

function isCompactionAllowedByOperator(): boolean {
	const allow = process.env.PI_SHELL_ACP_ALLOW_COMPACTION?.trim().toLowerCase();
	return allow === "1" || allow === "true" || allow === "yes";
}

function shellQuote(value: string): string {
	return `'${value.replace(/'/g, `'"'"'`)}'`;
}

function codexAutoCompactArgs(): string[] {
	return isCompactionAllowedByOperator() ? [] : [...CODEX_DISABLE_AUTO_COMPACT_ARGS];
}

export function resolveCodexMode(): CodexMode {
	const raw = process.env.PI_SHELL_ACP_CODEX_MODE?.trim().toLowerCase();
	if (raw === undefined || raw === "") return DEFAULT_CODEX_MODE;
	if (raw === "read-only" || raw === "auto" || raw === "full-access") return raw;
	// "Never warn. Throw." — silently falling back to DEFAULT_CODEX_MODE
	// (which is full-access) on a typo would land the operator on the most
	// permissive sandbox when they likely intended a tighter one. Make the
	// failure loud at the launch surface so the typo is fixed, not papered
	// over.
	throw new Error(
		`Invalid PI_SHELL_ACP_CODEX_MODE=${process.env.PI_SHELL_ACP_CODEX_MODE}: expected one of "read-only", "auto", "full-access".`,
	);
}

function codexModeArgs(): string[] {
	return [...CODEX_MODE_ARGS[resolveCodexMode()]];
}

function resolveCodexAcpLaunch(): AcpLaunchSpec {
	const override = process.env.CODEX_ACP_COMMAND?.trim();
	// codex-rs merges `-c key=value` flags left-to-right, with later values
	// for the same key winning. We append our mode + compaction guard *after*
	// the operator's CODEX_ACP_COMMAND override (see the override branch
	// below: `${override} ${ourFlags}`), so pi-shell-acp's policy always wins
	// against any `-c approval_policy=…` / `-c sandbox_mode=…` /
	// `-c model_auto_compact_token_limit=…` the operator may have inlined.
	// This is intentional — the env knobs (PI_SHELL_ACP_CODEX_MODE,
	// PI_SHELL_ACP_ALLOW_COMPACTION) are the supported way to change these
	// policies, not CODEX_ACP_COMMAND.
	const allArgs = [...codexModeArgs(), ...codexAutoCompactArgs()];
	if (override) {
		const command = allArgs.length > 0 ? `${override} ${allArgs.map(shellQuote).join(" ")}` : override;
		return {
			command: "bash",
			args: ["-lc", command],
			source: "env:CODEX_ACP_COMMAND",
		};
	}

	return {
		command: "codex-acp",
		args: allArgs,
		source: "PATH:codex-acp",
	};
}

// Cached so we run ldd at most once per process — libc never changes mid-run.
let cachedClaudeCodeExecutable: string | null | undefined;

function detectLinuxLibc(): "glibc" | "musl" {
	// `ldd --version` prints "(GNU libc) X.Y" on glibc and the literal token
	// "musl libc" on musl. The check is deliberately tolerant — anything we
	// can't classify falls through to glibc, which is the default on every
	// mainstream Linux distro this bridge is run on.
	try {
		const out = execFileSync("ldd", ["--version"], {
			encoding: "utf8",
			timeout: 2000,
			stdio: ["ignore", "pipe", "pipe"],
		});
		if (/musl/i.test(out)) return "musl";
	} catch {
		// ldd missing or non-zero: musl distros sometimes exit non-zero from
		// `ldd --version`; check the captured stderr opportunistically too.
	}
	return "glibc";
}

function resolveClaudeCodeExecutable(): string | undefined {
	if (cachedClaudeCodeExecutable !== undefined) {
		return cachedClaudeCodeExecutable ?? undefined;
	}

	const envOverride = process.env.PI_SHELL_ACP_CLAUDE_CODE_PATH?.trim();
	if (envOverride) {
		cachedClaudeCodeExecutable = envOverride;
		return envOverride;
	}

	// Why we override at all:
	// claude-agent-sdk@0.2.114+ ships a libc-aware native binary as a sibling
	// optionalDependency (e.g. `claude-agent-sdk-linux-arm64-musl`). Its
	// auto-detect probes `[musl, glibc]` in that fixed order, picks whichever
	// is hoisted into node_modules, and treats finding *either* package as
	// success. pnpm — including pi's global install — does not filter
	// optionalDependencies by `libc`, so on a glibc host both variants land in
	// the store and the musl ELF wins. Spawning it then fails with ENOENT
	// because the musl interpreter (`/lib/ld-musl-<arch>.so.1`) is absent on
	// glibc systems (NixOS, Debian, etc.), surfacing through the ACP bridge as
	// "Internal error" with no useful tail. We sidestep the auto-detect by
	// resolving the variant ourselves with libc taken into account, then fall
	// back to the bundled pure-JS `cli.js` if no native variant is reachable.
	const require = createRequire(import.meta.url);
	const arch = process.arch;
	let nativeCandidates: string[];
	if (process.platform === "linux") {
		const libc = detectLinuxLibc();
		nativeCandidates =
			libc === "musl" ? [`linux-${arch}-musl`, `linux-${arch}`] : [`linux-${arch}`, `linux-${arch}-musl`];
	} else {
		nativeCandidates = [`${process.platform}-${arch}`];
	}

	const binaryName = process.platform === "win32" ? "claude.exe" : "claude";
	for (const variant of nativeCandidates) {
		try {
			const pkgJsonPath = require.resolve(`@anthropic-ai/claude-agent-sdk-${variant}/package.json`);
			const candidate = join(dirname(pkgJsonPath), binaryName);
			if (existsSync(candidate)) {
				cachedClaudeCodeExecutable = candidate;
				return candidate;
			}
		} catch {
			// Package not present for this variant — try the next.
		}
	}

	try {
		const sdkPkgPath = require.resolve("@anthropic-ai/claude-agent-sdk/package.json");
		const cliJs = join(dirname(sdkPkgPath), "cli.js");
		if (existsSync(cliJs)) {
			cachedClaudeCodeExecutable = cliJs;
			return cliJs;
		}
	} catch {
		// SDK is required by claude-agent-acp; if it's truly missing there is
		// nothing we can repair from here. Let the SDK's own auto-detect run.
	}

	cachedClaudeCodeExecutable = null;
	return undefined;
}

// Build the `_meta.claudeCode.options` payload that pi-shell-acp hands to
// claude-agent-acp on session_new / session_resume / session_load.
//
// Design contract (see AGENTS.md "Identity preservation, not config inheritance"):
//   - Tool surface is restricted to the pi baseline by default (Read/Bash/
//     Edit/Write) so the system prompt's advertised toolset and the SDK's
//     actual toolset match. Users can override per-config.
//   - Skills are injected explicitly via `plugins: [{type:"local", path}]`,
//     not by opening `settingSources` to read `~/.claude/skills/`.
//   - Permissions are granted explicitly via `settings.permissions.allow`
//     wildcards. Combined with claude-agent-acp's own `permissionMode`
//     resolution (which it derives from the user's filesystem
//     `~/.claude/settings.json` `defaultMode` and we cannot override via
//     `_meta`), this delivers de facto YOLO for the listed tools without
//     touching the user's native Claude Code permission default.
//   - `settingSources` defaults to `[]` (SDK isolation mode): no
//     filesystem-sourced settings, MCP, hooks, env, or plugins from
//     `~/.claude/`. The bridge's `mcpServers` argument and the explicit
//     plugin paths above are the only injection surface.
//   - `strict-mcp-config` is on by default at the index.ts layer so the
//     bridge MCP servers are the only MCP source.
//
// Claude Code's auto-injected identity (its built-in system prompt preset,
// model behavior, tool implementations) is not touched. Only the *operating
// surface* — what tools, MCP, skills, and permissions are present — is
// constrained to a pi-shaped envelope.
function buildClaudeSessionMeta(
	params: BackendSessionMetaParams,
	normalizedSystemPrompt: string | undefined,
): Record<string, any> {
	const claudeCodeOptions: Record<string, any> = {
		...(params.modelId ? { model: params.modelId } : {}),
		tools: [...params.tools],
		settingSources: [...params.settingSources],
		settings: {
			permissions: {
				allow: [...params.permissionAllow],
			},
		},
	};
	if (params.skillPlugins.length > 0) {
		claudeCodeOptions.plugins = params.skillPlugins.map((path) => ({ type: "local", path }));
	}
	// Disallowed tools — passed through to claude-agent-acp's userProvidedOptions
	// spread (acp-agent.ts:1768), where the agent merges its own default
	// ["AskUserQuestion"] on top. We only emit the field when non-empty so
	// operators who set `disallowedTools: []` in pi-shell-acp config opt fully
	// out of the bridge's deferred-tool muting (the agent's own
	// AskUserQuestion mute still applies — that's claude-agent-acp's call,
	// not ours).
	if (params.disallowedTools.length > 0) {
		claudeCodeOptions.disallowedTools = [...params.disallowedTools];
	}
	const claudeCodeExecutable = resolveClaudeCodeExecutable();
	if (claudeCodeExecutable) {
		claudeCodeOptions.pathToClaudeCodeExecutable = claudeCodeExecutable;
	}
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

// ============================================================================
// Claude config overlay — isolate claude-agent-acp's SettingsManager from
// the operator's `~/.claude/settings.json` permissionMode pickup.
// ============================================================================
//
// claude-agent-acp's SettingsManager loads `~/.claude/settings.json` directly
// (independent of the SDK's `settingSources` option) and resolves
// `permissions.defaultMode` into the SDK's top-level `Options.permissionMode`.
// pi-shell-acp cannot override this via `_meta.claudeCode.options` — the
// agent hardcodes the resolved value after spreading user-provided options
// (acp-agent.ts:1761). The operator's preferred native default mode (often
// `"auto"`) therefore leaks into pi-shell-acp sessions even when we set
// `settingSources: []`.
//
// CLAUDE_CONFIG_DIR is the env var that determines where SettingsManager
// looks for the user-level `settings.json`. By spawning claude-agent-acp
// with CLAUDE_CONFIG_DIR pointing at a pi-owned overlay directory, we
// redirect the SettingsManager read to a settings.json *we* control while
// keeping the rest of `~/.claude/` (credentials, projects, agents, plugins,
// skills caches) reachable through symlinks. The overlay's settings.json is
// minimal — only the fields we need to override. No filesystem inheritance
// of hooks, env, or other ambient values.
//
// Overlay structure:
//
//   ~/.pi/agent/claude-config-overlay/
//   ├── settings.json         (pi-shell-acp authored — minimal override)
//   ├── .credentials.json     -> ~/.claude/.credentials.json (symlink)
//   ├── projects/             -> ~/.claude/projects/        (symlink)
//   ├── agents/               -> ~/.claude/agents/          (symlink)
//   └── ... (every other entry of ~/.claude/ symlinked to its real path)
//
// The overlay is rebuilt on every claude session bootstrap (idempotent), so
// new entries appearing in `~/.claude/` later (a new project directory, etc.)
// surface on the next launch without manual intervention.
const CLAUDE_REAL_CONFIG_DIR = join(homedir(), ".claude");
export const CLAUDE_CONFIG_OVERLAY_DIR = join(homedir(), ".pi", "agent", "claude-config-overlay");

// Minimal settings.json content for the overlay. Only fields we have a
// reason to pin live here. Currently we override `permissions.defaultMode`
// to neutralize the operator's native `"auto"` setting, which would
// otherwise apply to pi-shell-acp sessions and (a) trigger Claude Code's
// auto mode classifier inside an ACP session, (b) be invisible to operators
// who only set it for their direct Claude Code use. With our explicit
// `tools` surface and `permissionAllow` wildcard list, `"default"` mode
// auto-passes every tool we actually expose — no prompts in practice — and
// degrades gracefully if the surface ever expands without an allow update.
function overlaySettingsJson(): string {
	return `${JSON.stringify({ permissions: { defaultMode: "default" } }, null, 2)}\n`;
}

export function ensureClaudeConfigOverlay(
	realDir: string = CLAUDE_REAL_CONFIG_DIR,
	overlayDir: string = CLAUDE_CONFIG_OVERLAY_DIR,
): void {
	mkdirSync(overlayDir, { recursive: true });

	// Settings.json — always written. Cheap, unconditional rewrite ensures the
	// override is in place even if a prior process or operator edited it.
	writeFileSync(join(overlayDir, "settings.json"), overlaySettingsJson(), "utf8");

	if (!existsSync(realDir)) return;

	// Symlink every other entry from the real config dir into the overlay.
	// Idempotent — preserves correct symlinks, replaces wrong ones.
	for (const entry of readdirSync(realDir)) {
		if (entry === "settings.json") continue;
		const realPath = join(realDir, entry);
		const overlayPath = join(overlayDir, entry);

		try {
			const existing = lstatSync(overlayPath);
			if (existing.isSymbolicLink()) {
				if (readlinkSync(overlayPath) === realPath) continue;
				unlinkSync(overlayPath);
			} else {
				// Wrong file type at this path — remove and replace with symlink.
				rmSync(overlayPath, { recursive: true, force: true });
			}
		} catch {
			// Doesn't exist — fall through to create.
		}

		try {
			symlinkSync(realPath, overlayPath);
		} catch (error) {
			// Best-effort: a symlink failure should not block the session bootstrap.
			// Operator can inspect the overlay manually if a flow breaks.
			console.error(
				`[pi-shell-acp:claude-overlay] symlink failed for ${entry}: ${error instanceof Error ? error.message : String(error)}`,
			);
		}
	}
}

// ============================================================================
// Codex config overlay — isolate codex-acp's Config loader from the
// operator's `~/.codex/config.toml` field pickup.
// ============================================================================
//
// codex-acp loads the codex-rs `Config` struct via
// `Config::load_with_cli_overrides_and_harness_overrides`
// (codex-acp/src/lib.rs:47). That call reads
// `${CODEX_HOME:-~/.codex}/config.toml` and merges in our `-c key=value`
// flags. Fields the operator sets in their personal config.toml that we do
// NOT cover with `-c` flags — `model`, `model_reasoning_effort`,
// `personality`, `[projects."*"].trust_level`, `[notice.*]` — therefore
// leak straight into pi-shell-acp sessions.
//
// We mirror the Claude-side `CLAUDE_CONFIG_DIR` overlay shape: point
// `CODEX_HOME` at a pi-owned overlay directory, write a minimal
// `config.toml` there, and symlink every other entry from `~/.codex/`
// (`auth.json`, `sessions`, `history.jsonl`, `skills`, `memories`,
// `rules`, `cache`, ...) so nothing operator-facing breaks. The overlay is
// rebuilt idempotently on every codex spawn so newly-created entries in
// `~/.codex/` show up on the next launch automatically. process.env wins
// over bridgeEnvDefaults, so an operator who explicitly exports CODEX_HOME
// keeps full control.
const CODEX_REAL_CONFIG_DIR = join(homedir(), ".codex");
export const CODEX_CONFIG_OVERLAY_DIR = join(homedir(), ".pi", "agent", "codex-config-overlay");

// Minimal codex config.toml content for the overlay.
//
// We do NOT inherit the operator's personal config.toml (model,
// personality, model_reasoning_effort, projects.trust_level, etc.).
// pi-shell-acp pins every operating-surface value it cares about via `-c`
// CLI overrides at launch (approval_policy, sandbox_mode,
// model_auto_compact_token_limit, model where needed). Anything not pinned
// falls through to codex-rs's own hard-coded defaults — by design.
//
// The header is the only required content; codex-rs accepts an effectively
// empty TOML file. We keep the comment so an operator who inspects the
// overlay knows it is pi-managed and any manual edit will be overwritten.
function overlayCodexConfigToml(): string {
	return "# pi-shell-acp managed overlay — do not edit manually.\n# Operator config at ~/.codex/config.toml is intentionally NOT inherited.\n";
}

export function ensureCodexConfigOverlay(
	realDir: string = CODEX_REAL_CONFIG_DIR,
	overlayDir: string = CODEX_CONFIG_OVERLAY_DIR,
): void {
	mkdirSync(overlayDir, { recursive: true });

	// config.toml — always written. Cheap, unconditional rewrite ensures the
	// override is in place even if a prior process or operator edited it.
	writeFileSync(join(overlayDir, "config.toml"), overlayCodexConfigToml(), "utf8");

	if (!existsSync(realDir)) return;

	// Symlink every other entry from the real config dir into the overlay.
	// Idempotent — preserves correct symlinks, replaces wrong ones.
	for (const entry of readdirSync(realDir)) {
		if (entry === "config.toml") continue;
		const realPath = join(realDir, entry);
		const overlayPath = join(overlayDir, entry);

		try {
			const existing = lstatSync(overlayPath);
			if (existing.isSymbolicLink()) {
				if (readlinkSync(overlayPath) === realPath) continue;
				unlinkSync(overlayPath);
			} else {
				rmSync(overlayPath, { recursive: true, force: true });
			}
		} catch {
			// Doesn't exist — fall through to create.
		}

		try {
			symlinkSync(realPath, overlayPath);
		} catch (error) {
			console.error(
				`[pi-shell-acp:codex-overlay] symlink failed for ${entry}: ${error instanceof Error ? error.message : String(error)}`,
			);
		}
	}
}

function buildCodexBootstrapPromptAugment(augmentText: string): PromptContentBlock[] | undefined {
	const text = augmentText?.trim();
	if (!text) return undefined;
	// Codex ACP has no _meta.systemPrompt.append-style extension exposed to us;
	// the spec-baseline identity-delivery carrier is a ContentBlock on the
	// first prompt turn. We prepend one text block so the engraving lands in
	// the turn context the model actually sees on session bootstrap.
	return [{ type: "text", text }];
}

const ACP_BACKEND_ADAPTERS: Record<AcpBackend, AcpBackendAdapter> = {
	claude: {
		id: "claude",
		stderrLabel: "claude-agent-acp stderr",
		resolveLaunch: resolveClaudeAcpLaunch,
		buildSessionMeta: buildClaudeSessionMeta,
		// Engraving rides on _meta.systemPrompt.append; no first-prompt
		// ContentBlock augmentation needed for Claude.
		bridgeEnvDefaults: {
			// Disable Claude Code's built-in auto-compaction. pi-shell-acp keeps pi
			// as the single context-management authority; if the backend silently
			// compacts inside the same ACP session, pi has no way to react and
			// session continuity drifts. Operators can override these from their
			// shell — process.env wins below.
			DISABLE_AUTO_COMPACT: "1",
			DISABLE_COMPACT: "1",
			// Redirect claude-agent-acp's SettingsManager away from
			// ~/.claude/settings.json so the operator's native `permissions.defaultMode`
			// (often "auto") does not silently apply to pi-shell-acp sessions. The
			// overlay directory is rebuilt at every spawn (see
			// ensureClaudeConfigOverlay below). process.env wins, so an operator who
			// explicitly exports CLAUDE_CONFIG_DIR keeps full control.
			CLAUDE_CONFIG_DIR: CLAUDE_CONFIG_OVERLAY_DIR,
		},
	},
	codex: {
		id: "codex",
		stderrLabel: "codex-acp stderr",
		resolveLaunch: resolveCodexAcpLaunch,
		buildSessionMeta: () => undefined,
		buildBootstrapPromptAugment: buildCodexBootstrapPromptAugment,
		bridgeEnvDefaults: {
			// Redirect codex-rs's Config loader away from ~/.codex/config.toml so
			// the operator's personal model/personality/reasoning_effort etc. do
			// NOT silently apply to pi-shell-acp sessions. The overlay directory
			// is rebuilt at every spawn (see ensureCodexConfigOverlay above).
			// process.env wins, so an operator who explicitly exports CODEX_HOME
			// keeps full control.
			CODEX_HOME: CODEX_CONFIG_OVERLAY_DIR,
		},
		// codex-rs does not expose a boolean/env auto-compaction toggle like
		// Claude Code. It does expose the same behavior as a config threshold:
		// model_auto_compact_token_limit. resolveCodexAcpLaunch() raises that
		// threshold to i64::MAX via `-c`, keeping manual `/compact` available
		// while preventing silent backend compaction in daily ACP sessions.
	},
};

export function resolveAcpBackendAdapter(backend: AcpBackend): AcpBackendAdapter {
	if (backend == null) {
		throw new Error("ACP backend is required.");
	}
	const adapter = ACP_BACKEND_ADAPTERS[backend];
	if (!adapter) {
		throw new Error(`Unknown ACP backend: ${String(backend)}. Expected one of: claude, codex`);
	}
	return adapter;
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
	const bootstrapPromptAugment = record["bootstrapPromptAugment"];
	if (!(bootstrapPromptAugment == null || typeof bootstrapPromptAugment === "string")) return undefined;
	return {
		sessionKey,
		acpSessionId: record["acpSessionId"] as string,
		cwd: record["cwd"] as string,
		systemPromptAppend: (systemPromptAppend ?? null) as string | null,
		bootstrapPromptAugment: (bootstrapPromptAugment ?? null) as string | null,
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
		bootstrapPromptAugment: session.bootstrapPromptAugment ?? null,
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

// bootstrapPromptAugment is intentionally NOT part of compatibility checks.
// It is a one-shot prepend consumed exactly once at session bootstrap
// (see armBootstrapPromptAugment + bootstrapPromptAugmentPending). Once the
// first prompt of a new session has been sent, the augment value no longer
// affects anything the backend sees on later turns, so comparing it across
// turns would force a fresh session for any caller that chose to vary the
// augment over time. Excluding it keeps the bridge prompt cache alive across
// reuse turns while preserving the fire-and-forget delivery contract.
function isSessionCompatible(
	session: Pick<
		AcpBridgeSession,
		"cwd" | "backend" | "systemPromptAppend" | "bridgeConfigSignature" | "contextMessageSignatures"
	>,
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

function buildSessionMeta(
	params: EnsureBridgeSessionParams,
	normalizedSystemPrompt: string | undefined,
): Record<string, any> | undefined {
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
	const fromModel = session.modelId;
	const setModel = (session.connection as any).unstable_setSessionModel;
	if (typeof setModel !== "function") {
		logBridgeModelSwitch(session, {
			path: "bootstrap",
			outcome: "unsupported",
			fromModel,
			toModel: requestedModelId,
		});
		return;
	}
	try {
		await setModel.call(session.connection, {
			sessionId: session.acpSessionId,
			modelId: requestedModelId,
		});
		session.modelId = requestedModelId;
		logBridgeModelSwitch(session, {
			path: "bootstrap",
			outcome: "applied",
			fromModel,
			toModel: requestedModelId,
		});
	} catch (error) {
		logBridgeModelSwitch(session, {
			path: "bootstrap",
			outcome: "failed",
			fromModel,
			toModel: requestedModelId,
			reason: error instanceof Error ? error.message : String(error),
		});
		throw error;
	}
}

function isChildExited(child: ChildProcessByStdio<any, any, any>): boolean {
	return child.exitCode !== null || child.signalCode !== null;
}

function awaitChildExit(child: ChildProcessByStdio<any, any, any>, timeoutMs: number): Promise<"exited" | "timeout"> {
	if (isChildExited(child)) return Promise.resolve("exited");
	return new Promise((resolve) => {
		const timer = setTimeout(() => resolve("timeout"), timeoutMs);
		timer.unref?.();
		child.once("exit", () => {
			clearTimeout(timer);
			resolve("exited");
		});
	});
}

function killProcessTree(child: ChildProcessByStdio<any, any, any>, sessionKey: string, backend: AcpBackend): void {
	const pid = child.pid;
	if (!pid) return;
	if (process.platform !== "win32") {
		try {
			process.kill(-pid, "SIGTERM");
			const timer = setTimeout(() => {
				if (isChildExited(child)) return;
				try {
					process.kill(-pid, "SIGKILL");
					logBridgeOrphanKill(sessionKey, pid, backend);
				} catch {
					// ignore
				}
			}, 1500);
			timer.unref?.();
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
	let closedRemote: "ok" | "fail" | "skip" = "skip";
	if (options.closeRemote && session.capabilities.closeSession && session.acpSessionId) {
		try {
			await (session.connection as any).unstable_closeSession?.({ sessionId: session.acpSessionId });
			closedRemote = "ok";
		} catch {
			closedRemote = "fail";
		}
	}
	const childPid = session.child.pid;
	killProcessTree(session.child, session.key, session.backend);
	const childExit = await awaitChildExit(session.child, 2000);
	logBridgeShutdown(session, {
		closeRemote: options.closeRemote,
		invalidatePersisted: options.invalidatePersisted,
		childPid,
		closedRemote,
		childExit,
	});
}

function formatBootstrapPayload(payload: Record<string, unknown>): string {
	return Object.entries(payload)
		.filter(([, v]) => v !== undefined && v !== null && v !== "")
		.map(([k, v]) => {
			const str = typeof v === "string" ? v : String(v);
			return /[\s"]/.test(str) ? `${k}="${str.replace(/"/g, '\\"')}"` : `${k}=${str}`;
		})
		.join(" ");
}

type BootstrapInvalidationReason = "incompatible_config" | "bootstrap_exhausted";

function logBridgeBootstrap(session: AcpBridgeSession, extra?: Record<string, unknown>): void {
	const line = formatBootstrapPayload({
		path: session.bootstrapPath,
		backend: session.backend,
		sessionKey: session.key,
		acpSessionId: session.acpSessionId,
		persistedAcpSessionId: session.persistedAcpSessionId,
		...(extra || {}),
	});
	console.error(`[pi-shell-acp:bootstrap] ${line}`);
}

function logBridgeBootstrapFallback(sessionKey: string, from: "resume" | "load", error: unknown): void {
	const reason = error instanceof Error ? error.message : String(error);
	const line = formatBootstrapPayload({
		from,
		sessionKey,
		reason: reason.slice(0, 200),
	});
	console.error(`[pi-shell-acp:bootstrap-fallback] ${line}`);
}

function logBridgeBootstrapInvalidate(
	sessionKey: string,
	reason: BootstrapInvalidationReason,
	previousAcpSessionId?: string,
): void {
	const line = formatBootstrapPayload({
		sessionKey,
		reason,
		previousAcpSessionId,
	});
	console.error(`[pi-shell-acp:bootstrap-invalidate] ${line}`);
}

export type CancelOutcome = "dispatched" | "unsupported" | "failed";

export type ModelSwitchOutcome = "applied" | "unsupported" | "failed";
export type ModelSwitchPath = "bootstrap" | "reuse";

function logBridgeModelSwitch(
	session: AcpBridgeSession,
	extra: {
		path: ModelSwitchPath;
		outcome: ModelSwitchOutcome;
		fromModel?: string;
		toModel?: string;
		reason?: string;
		fallback?: "new_session" | "none";
	},
): void {
	const line = formatBootstrapPayload({
		path: extra.path,
		outcome: extra.outcome,
		sessionKey: session.key,
		backend: session.backend,
		acpSessionId: session.acpSessionId,
		fromModel: extra.fromModel,
		toModel: extra.toModel,
		fallback: extra.fallback,
		reason: extra.reason ? extra.reason.slice(0, 200) : undefined,
	});
	console.error(`[pi-shell-acp:model-switch] ${line}`);
}

function logBridgeCancel(session: AcpBridgeSession, outcome: CancelOutcome, reason?: string): void {
	const line = formatBootstrapPayload({
		sessionKey: session.key,
		backend: session.backend,
		acpSessionId: session.acpSessionId,
		outcome,
		reason: reason ? reason.slice(0, 200) : undefined,
	});
	console.error(`[pi-shell-acp:cancel] ${line}`);
}

function logBridgeShutdown(
	session: AcpBridgeSession,
	extra: {
		closeRemote: boolean;
		invalidatePersisted: boolean;
		childPid: number | undefined;
		closedRemote: "ok" | "fail" | "skip";
		childExit: "exited" | "timeout";
	},
): void {
	const line = formatBootstrapPayload({
		sessionKey: session.key,
		backend: session.backend,
		acpSessionId: session.acpSessionId,
		...extra,
	});
	console.error(`[pi-shell-acp:shutdown] ${line}`);
}

function logBridgeOrphanKill(sessionKey: string, pid: number, backend: AcpBackend): void {
	const line = formatBootstrapPayload({
		sessionKey,
		backend,
		pid,
		signal: "SIGKILL",
	});
	console.error(`[pi-shell-acp:orphan-kill] ${line}`);
}

function isStrictBootstrapEnabled(): boolean {
	const v = process.env.PI_SHELL_ACP_STRICT_BOOTSTRAP?.trim().toLowerCase();
	return v === "1" || v === "true" || v === "yes";
}

async function createBridgeProcess(params: EnsureBridgeSessionParams): Promise<AcpBridgeSession> {
	const adapter = resolveAcpBackendAdapter(params.backend);
	const launch = adapter.resolveLaunch();
	// Adapter defaults first, process.env last → operator's shell always wins.
	// PI_SHELL_ACP_ALLOW_COMPACTION=1 disables both pi-side and backend-side
	// compaction guards for this process.
	const bridgeEnvDefaults = isCompactionAllowedByOperator() ? undefined : adapter.bridgeEnvDefaults;
	// Refresh the claude config overlay before every claude session bootstrap.
	// Idempotent — picks up any new entries that appeared in ~/.claude/ since
	// the last run (e.g. a freshly created project) without manual intervention.
	if (params.backend === "claude" && bridgeEnvDefaults?.CLAUDE_CONFIG_DIR === CLAUDE_CONFIG_OVERLAY_DIR) {
		try {
			ensureClaudeConfigOverlay();
		} catch (error) {
			console.error(
				`[pi-shell-acp:claude-overlay] failed to prepare overlay; falling back to operator's CLAUDE_CONFIG_DIR if any: ${error instanceof Error ? error.message : String(error)}`,
			);
		}
	}
	if (params.backend === "codex" && bridgeEnvDefaults?.CODEX_HOME === CODEX_CONFIG_OVERLAY_DIR) {
		try {
			ensureCodexConfigOverlay();
		} catch (error) {
			console.error(
				`[pi-shell-acp:codex-overlay] failed to prepare overlay; falling back to operator's CODEX_HOME if any: ${error instanceof Error ? error.message : String(error)}`,
			);
		}
	}
	const childEnv = { ...bridgeEnvDefaults, ...process.env };
	const child = spawn(launch.command, launch.args, {
		cwd: params.cwd,
		env: childEnv,
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
		bootstrapPromptAugment: normalizeText(params.bootstrapPromptAugment),
		settingSources: [...params.settingSources],
		strictMcpConfig: params.strictMcpConfig,
		mcpServers: [...params.mcpServers],
		tools: [...params.tools],
		skillPlugins: [...params.skillPlugins],
		permissionAllow: [...params.permissionAllow],
		disallowedTools: [...params.disallowedTools],
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

function armBootstrapPromptAugment(session: AcpBridgeSession): void {
	if (session.bootstrapPath !== "new") return;
	const augmentText = session.bootstrapPromptAugment;
	if (!augmentText) return;
	const adapter = resolveAcpBackendAdapter(session.backend);
	const blocks = adapter.buildBootstrapPromptAugment?.(augmentText);
	if (blocks && blocks.length > 0) {
		session.bootstrapPromptAugmentPending = blocks;
	}
}

async function startNewBridgeSession(
	params: EnsureBridgeSessionParams,
	invalidationHint?: { reason: BootstrapInvalidationReason; previousAcpSessionId: string },
): Promise<AcpBridgeSession> {
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
		if (invalidationHint) {
			session.persistedAcpSessionId = invalidationHint.previousAcpSessionId;
		}
		armBootstrapPromptAugment(session);
		await enforceRequestedSessionModel(session, params.modelId);
		bridgeSessions.set(params.sessionKey, session);
		persistBridgeSessionRecord(session);
		logBridgeBootstrap(
			session,
			invalidationHint ? { invalidated: true, invalidationReason: invalidationHint.reason } : undefined,
		);
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
				logBridgeBootstrap(session);
				return session;
			} catch (error) {
				shouldInvalidatePersisted = true;
				logBridgeBootstrapFallback(params.sessionKey, "resume", error);
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
				logBridgeBootstrap(session);
				return session;
			} catch (error) {
				shouldInvalidatePersisted = true;
				logBridgeBootstrapFallback(params.sessionKey, "load", error);
			}
		}

		if (shouldInvalidatePersisted) {
			logBridgeBootstrapInvalidate(params.sessionKey, "bootstrap_exhausted", record.acpSessionId);
			deletePersistedSessionRecord(params.sessionKey);
			if (isStrictBootstrapEnabled()) {
				throw new Error(
					`[pi-shell-acp] bootstrap_exhausted: resume and load both failed for sessionKey=${params.sessionKey} previousAcpSessionId=${record.acpSessionId}`,
				);
			}
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
		armBootstrapPromptAugment(session);
		await enforceRequestedSessionModel(session, params.modelId);
		bridgeSessions.set(params.sessionKey, session);
		persistBridgeSessionRecord(session);
		logBridgeBootstrap(
			session,
			shouldInvalidatePersisted ? { invalidated: true, invalidationReason: "bootstrap_exhausted" } : undefined,
		);
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
	const normalizedBootstrapAugment = normalizeText(params.bootstrapPromptAugment);
	const normalizedParams: EnsureBridgeSessionParams = {
		...params,
		systemPromptAppend: normalizedSystemPrompt,
		bootstrapPromptAugment: normalizedBootstrapAugment,
	};
	const existing = bridgeSessions.get(params.sessionKey);
	const existingCompatible = existing ? isSessionCompatible(existing, normalizedParams, normalizedSystemPrompt) : false;
	if (existing && existingCompatible && !existing.closed && isChildAlive(existing.child)) {
		if (params.modelId && existing.modelId !== params.modelId) {
			const fromModel = existing.modelId;
			const toModel = params.modelId;
			const setModel = (existing.connection as any).unstable_setSessionModel;
			if (typeof setModel !== "function") {
				logBridgeModelSwitch(existing, {
					path: "reuse",
					outcome: "unsupported",
					fromModel,
					toModel,
					fallback: "new_session",
				});
				await closeBridgeSession(params.sessionKey);
				return await startNewBridgeSession(normalizedParams);
			}
			try {
				await setModel.call(existing.connection, {
					sessionId: existing.acpSessionId,
					modelId: toModel,
				});
				existing.modelId = toModel;
				logBridgeModelSwitch(existing, {
					path: "reuse",
					outcome: "applied",
					fromModel,
					toModel,
				});
			} catch (error) {
				logBridgeModelSwitch(existing, {
					path: "reuse",
					outcome: "failed",
					fromModel,
					toModel,
					fallback: "new_session",
					reason: error instanceof Error ? error.message : String(error),
				});
				await closeBridgeSession(params.sessionKey);
				return await startNewBridgeSession(normalizedParams);
			}
		}
		existing.settingSources = [...params.settingSources];
		existing.strictMcpConfig = params.strictMcpConfig;
		existing.tools = [...params.tools];
		existing.skillPlugins = [...params.skillPlugins];
		existing.permissionAllow = [...params.permissionAllow];
		existing.disallowedTools = [...params.disallowedTools];
		existing.bridgeConfigSignature = params.bridgeConfigSignature;
		existing.contextMessageSignatures = [...params.contextMessageSignatures];
		existing.bootstrapPath = "reuse";
		persistBridgeSessionRecord(existing);
		logBridgeBootstrap(existing);
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
			logBridgeBootstrapInvalidate(params.sessionKey, "incompatible_config", persisted.acpSessionId);
			deletePersistedSessionRecord(params.sessionKey);
			return await startNewBridgeSession(normalizedParams, {
				reason: "incompatible_config",
				previousAcpSessionId: persisted.acpSessionId,
			});
		}
		return await bootstrapPersistedBridgeSession(normalizedParams, persisted);
	}

	return await startNewBridgeSession(normalizedParams);
}

export function setActivePromptHandler(session: AcpBridgeSession, handler: PendingPromptHandler | undefined): void {
	session.activePromptHandler = handler;
}

export async function sendPrompt(session: AcpBridgeSession, prompt: PromptContentBlock[]): Promise<PromptResponse> {
	// First prompt after a bootstrapPath="new" session may carry an adapter-
	// supplied ContentBlock prepend (the rendered engraving on Codex, etc.).
	// Consume the pending slot exactly once so subsequent turns stay clean.
	const pending = session.bootstrapPromptAugmentPending;
	session.bootstrapPromptAugmentPending = undefined;
	const effectivePrompt = pending && pending.length > 0 ? [...pending, ...prompt] : prompt;
	return await (session.connection as any).prompt({
		sessionId: session.acpSessionId,
		prompt: effectivePrompt,
	});
}

export async function cancelActivePrompt(session: AcpBridgeSession): Promise<CancelOutcome> {
	const cancel = (session.connection as any).cancel;
	if (typeof cancel !== "function") {
		logBridgeCancel(session, "unsupported");
		return "unsupported";
	}
	try {
		await cancel.call(session.connection, { sessionId: session.acpSessionId });
		logBridgeCancel(session, "dispatched");
		return "dispatched";
	} catch (error) {
		const reason = error instanceof Error ? error.message : String(error);
		logBridgeCancel(session, "failed", reason);
		return "failed";
	}
}

export async function closeBridgeSession(sessionKey: string, options: CloseBridgeSessionOptions = {}): Promise<void> {
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
	const diagnostic = session
		? `\n\n[pi-shell-acp session]\n${JSON.stringify(describeBridgeSession(session), null, 2)}`
		: "";
	const stderrTail = session?.stderrTail?.slice(-20)?.join("\n");
	const stderrBlock = stderrTail ? `\n\n[${session?.stderrLabel ?? "acp stderr"}]\n${stderrTail}` : "";
	return `${message}${diagnostic}${stderrBlock}`;
}
